local harpoon = require('harpoon')
local popup = require('plenary.popup')
local Marked = require('harpoon.mark')
local utils = require('harpoon.utils')
local log = require('harpoon.dev').log

local nsid = vim.api.nvim_create_namespace('harpoon')

local M = {}

Harpoon_win_id = nil
Harpoon_bufh = nil

-- We save before we close because we use the state of the buffer as the list
-- of items.
local function close_menu(force_save)
  force_save = force_save or false
  local global_config = harpoon.get_global_settings()

  if global_config.save_on_toggle or force_save then
    require('harpoon.ui').on_menu_save()
  end

  vim.api.nvim_win_close(Harpoon_win_id, true)

  Harpoon_win_id = nil
  Harpoon_bufh = nil
end

local function create_window()
  log.trace('_create_window()')
  local config = harpoon.get_menu_config()
  local width = config.width or 60
  local height = config.height or 10
  local borderchars = config.borderchars or { '─', '│', '─', '│', '╭', '╮', '╯', '╰' }
  local bufnr = vim.api.nvim_create_buf(false, false)

  local Harpoon_win_id, win = popup.create(bufnr, {
    title = 'Harpoon',
    title_pos = 'right',
    titlehighlight = 'HarpoonTitle',
    highlight = 'HarpoonWindow',
    style = 'minimal',
    line = math.floor(((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    minwidth = width,
    minheight = height,
    borderchars = borderchars,
    borderhighlight = 'HarpoonBorder',
  })

  vim.api.nvim_set_option_value('winhl', 'Normal:HarpoonBorder', { win = win.border.win_id })

  return {
    bufnr = bufnr,
    win_id = Harpoon_win_id,
  }
end

local function get_menu_items()
  log.trace('_get_menu_items()')
  local lines = vim.api.nvim_buf_get_lines(Harpoon_bufh, 0, -1, true)
  local indices = {}

  for _, line in pairs(lines) do
    if not utils.is_white_space(line) then
      table.insert(indices, line)
    end
  end

  return indices
end

---@param file_name string
---@return string, string -- icon, hl_group
local function get_icon(file_name)
  if vim.fn.isdirectory(file_name) == 1 then
    return '', 'Normal'
  end

  local devicons = require('nvim-web-devicons')
  local extenstion = vim.fn.fnamemodify(file_name, ':e')
  return devicons.get_icon(file_name, extenstion, { default = true })
end

--- Sets the icon and it's highlight group
local function set_virtual_text()
  local lines = vim.api.nvim_buf_get_lines(Harpoon_bufh, 0, -1, true)

  for idx, _ in pairs(lines) do
    local file_name = Marked.get_marked_file_name(idx)
    local icon, hl_group = get_icon(file_name)

    vim.api.nvim_buf_set_extmark(Harpoon_bufh, nsid, idx - 1, 0, {
      virt_text = {
        { icon .. '  ', hl_group },
      },
      virt_text_pos = 'inline',
    })
  end

  -- vim.api.nvim_buf_set_extmark(Harpoon_bufh, nsid, 0, 0, {
  --   virt_text = {
  --     { ' ', 'Normal' },
  --   },
  --   virt_text_pos = 'inline',
  -- })
end

---@return string[]
function M.get_contents()
  local contents = {}
  for idx = 1, Marked.get_length() do
    local file = Marked.get_marked_file_name(idx)
    if file == '' then
      file = '(empty)'
    end
    contents[idx] = string.format('%s', file)
  end

  return contents
end

local function create_autocmds()
  local global_config = harpoon.get_global_settings()

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = Harpoon_bufh,
    callback = function()
      require('harpoon.ui').on_menu_save()
    end,
  })

  vim.api.nvim_create_autocmd('BufModifiedSet', {
    buffer = Harpoon_bufh,
    callback = function()
      vim.cmd('set nomodified')
      -- vim.api.nvim_set_option_value('nomodified', true, { buf = Harpoon_bufh })
    end,
  })

  if global_config.save_on_change then
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      buffer = Harpoon_bufh,
      callback = function()
        require('harpoon.ui').on_menu_save()
      end,
    })
  end

  vim.api.nvim_create_autocmd('BufLeave', {
    nested = true,
    once = true,
    -- silent = true,
    callback = function()
      require('harpoon.ui').toggle_quick_menu()
    end,
  })
end

function M.toggle_quick_menu()
  log.trace('toggle_quick_menu()')
  if Harpoon_win_id ~= nil and vim.api.nvim_win_is_valid(Harpoon_win_id) then
    close_menu()
    return
  end

  local curr_file = utils.normalize_path(vim.api.nvim_buf_get_name(0))
  vim.cmd(
    string.format(
      'autocmd Filetype harpoon '
        .. "let path = '%s' | call clearmatches() | "
        -- move the cursor to the line containing the current filename
        .. "call search('\\V'.path.'\\$') | "
        -- add a hl group to that line
        .. "call matchadd('HarpoonCurrentFile', '\\V'.path.'\\$')",
      curr_file:gsub('\\', '\\\\')
    )
  )

  local win_info = create_window()
  local contents = M.get_contents()

  Harpoon_win_id = win_info.win_id
  Harpoon_bufh = win_info.bufnr

  vim.api.nvim_set_option_value('number', true, { win = Harpoon_win_id })
  vim.api.nvim_buf_set_name(Harpoon_bufh, 'harpoon-menu')
  vim.api.nvim_buf_set_lines(Harpoon_bufh, 0, #contents, false, contents)
  vim.api.nvim_set_option_value('filetype', 'harpoon', { buf = Harpoon_bufh })
  vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = Harpoon_bufh })
  vim.api.nvim_set_option_value('bufhidden', 'delete', { buf = Harpoon_bufh })
  vim.api.nvim_buf_set_keymap(Harpoon_bufh, 'n', 'q', "<Cmd>lua require('harpoon.ui').toggle_quick_menu()<CR>", { silent = true })
  vim.api.nvim_buf_set_keymap(Harpoon_bufh, 'n', '<ESC>', "<Cmd>lua require('harpoon.ui').toggle_quick_menu()<CR>", { silent = true })
  vim.api.nvim_buf_set_keymap(Harpoon_bufh, 'n', '<CR>', "<Cmd>lua require('harpoon.ui').select_menu_item()<CR>", {})

  create_autocmds()
  set_virtual_text()

  -- vim.cmd(string.format("autocmd BufWriteCmd <buffer=%s> lua require('harpoon.ui').on_menu_save()", Harpoon_bufh))
  -- if global_config.save_on_change then
  --   vim.cmd(string.format("autocmd TextChanged,TextChangedI <buffer=%s> lua require('harpoon.ui').on_menu_save()", Harpoon_bufh))
  -- end
  -- vim.cmd(string.format('autocmd BufModifiedSet <buffer=%s> set nomodified', Harpoon_bufh))
  -- vim.cmd("autocmd BufLeave <buffer> ++nested ++once silent lua require('harpoon.ui').toggle_quick_menu()")
end

function M.select_menu_item()
  local idx = vim.fn.line('.')
  close_menu(true)
  M.nav_file(idx)
end

function M.on_menu_save()
  log.trace('on_menu_save()')
  Marked.set_mark_list(get_menu_items())
end

local function get_or_create_buffer(filename)
  local buf_exists = vim.fn.bufexists(filename) ~= 0
  if buf_exists then
    return vim.fn.bufnr(filename)
  end

  return vim.fn.bufadd(filename)
end

function M.nav_file(id)
  log.trace('nav_file(): Navigating to', id)
  local idx = Marked.get_index_of(id)
  if not Marked.valid_index(idx) then
    log.debug('nav_file(): No mark exists for id', id)
    return
  end

  local mark = Marked.get_marked_file(idx)
  local filename = vim.fs.normalize(mark.filename)
  local buf_id = get_or_create_buffer(filename)
  local set_row = not vim.api.nvim_buf_is_loaded(buf_id)

  local old_bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_set_current_buf(buf_id)
  vim.api.nvim_set_option_value('buflisted', true, { buf = buf_id })
  if set_row and mark.row and mark.col then
    vim.cmd(string.format(':call cursor(%d, %d)', mark.row, mark.col))
    log.debug(string.format('nav_file(): Setting cursor to row: %d, col: %d', mark.row, mark.col))
  end

  local old_bufinfo = vim.fn.getbufinfo(old_bufnr)
  if type(old_bufinfo) == 'table' and #old_bufinfo >= 1 then
    old_bufinfo = old_bufinfo[1]
    local no_name = old_bufinfo.name == ''
    local one_line = old_bufinfo.linecount == 1
    local unchanged = old_bufinfo.changed == 0
    if no_name and one_line and unchanged then
      vim.api.nvim_buf_delete(old_bufnr, {})
    end
  end
end

function M.location_window(options)
  local default_options = {
    relative = 'editor',
    style = 'minimal',
    width = 30,
    height = 15,
    row = 2,
    col = 2,
  }
  options = vim.tbl_extend('keep', options, default_options)

  local bufnr = options.bufnr or vim.api.nvim_create_buf(false, true)
  local win_id = vim.api.nvim_open_win(bufnr, true, options)

  return {
    bufnr = bufnr,
    win_id = win_id,
  }
end

function M.notification(text)
  local win_stats = vim.api.nvim_list_uis()[1]
  local win_width = win_stats.width

  local prev_win = vim.api.nvim_get_current_win()

  local info = M.location_window({
    width = 20,
    height = 2,
    row = 1,
    col = win_width - 21,
  })

  vim.api.nvim_buf_set_lines(info.bufnr, 0, 5, false, { '!!! Notification', text })
  vim.api.nvim_set_current_win(prev_win)

  return {
    bufnr = info.bufnr,
    win_id = info.win_id,
  }
end

function M.close_notification(bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

function M.nav_next()
  log.trace('nav_next()')
  local current_index = Marked.get_current_index()
  local number_of_items = Marked.get_length()

  if current_index == nil then
    current_index = 1
  else
    current_index = current_index + 1
  end

  if current_index > number_of_items then
    current_index = 1
  end
  M.nav_file(current_index)
end

function M.nav_prev()
  log.trace('nav_prev()')
  local current_index = Marked.get_current_index()
  local number_of_items = Marked.get_length()

  if current_index == nil then
    current_index = number_of_items
  else
    current_index = current_index - 1
  end

  if current_index < 1 then
    current_index = number_of_items
  end

  M.nav_file(current_index)
end

return M
