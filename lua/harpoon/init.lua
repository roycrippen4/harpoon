local Path = require('plenary.path')
local utils = require('harpoon.utils')

local config_path = vim.fn.stdpath('config')
local data_path = vim.fn.stdpath('data')
local user_config_path = string.format('%s/harpoon.json', config_path)
local cache_config_path = string.format('%s/harpoon.json', data_path)

local function set_keymaps()
  vim.keymap.set('n', '<C-V>', function()
    local curline = vim.api.nvim_get_current_line()
    local working_directory = vim.fn.getcwd() .. '/'
    vim.cmd('vs')
    vim.cmd('e ' .. working_directory .. curline)
  end, { buffer = true, noremap = true, silent = true })

  -- horizontal split (control+x)
  vim.keymap.set('n', '<C-x>', function()
    local curline = vim.api.nvim_get_current_line()
    local working_directory = vim.fn.getcwd() .. '/'
    vim.cmd('sp')
    vim.cmd('e ' .. working_directory .. curline)
  end, { buffer = true, noremap = true, silent = true })

  -- new tab (control+t)
  vim.keymap.set('n', '<C-t>', function()
    local curline = vim.api.nvim_get_current_line()
    local working_directory = vim.fn.getcwd() .. '/'
    vim.cmd('tabnew')
    vim.cmd('e ' .. working_directory .. curline)
  end, { buffer = true, noremap = true, silent = true })
end

local M = {}

local group = vim.api.nvim_create_augroup('Harpoon', { clear = true })
vim.api.nvim_create_autocmd({ 'BufLeave', 'VimLeave' }, {
  callback = function()
    require('harpoon.mark').store_offset()
  end,
  group = group,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'harpoon',
  group = group,
  callback = set_keymaps,
})

---@class Harpoon.Globals
---@field mark_branch? boolean
---@field save_on_toggle? boolean
---@field save_on_change? boolean
---@field excluded_filetypes? string[]

---@class Harpoon.Marks
---@field marks Harpoon.Mark[]

---@class Harpoon.Config
---@field global_settings Harpoon.Globals
---@field projects any
local HarpoonConfig = {}

-- tbl_deep_extend does not work the way you would think
local function merge_table_impl(t1, t2)
  for k, v in pairs(t2) do
    if type(v) == 'table' then
      if type(t1[k]) == 'table' then
        merge_table_impl(t1[k], v)
      else
        t1[k] = v
      end
    else
      t1[k] = v
    end
  end
end

local function mark_config_key(global_settings)
  global_settings = global_settings or M.get_global_settings()
  if global_settings.mark_branch then
    return utils.branch_key()
  else
    return utils.project_key()
  end
end

local function merge_tables(...)
  local out = {}
  for i = 1, select('#', ...) do
    merge_table_impl(out, select(i, ...))
  end
  return out
end

---@return Harpoon.Config
local function ensure_correct_config(config)
  local projects = config.projects
  local mark_key = mark_config_key(config.global_settings)
  if projects[mark_key] == nil then
    projects[mark_key] = {
      mark = { marks = {} },
    }
  end

  local proj = projects[mark_key]
  if proj.mark == nil then
    proj.mark = { marks = {} }
  end

  local marks = proj.mark.marks

  for idx, mark in pairs(marks) do
    if type(mark) == 'string' then
      mark = { filename = mark }
      marks[idx] = mark
    end

    marks[idx].filename = utils.normalize_path(mark.filename)
  end

  return config
end

local function expand_dir(config)
  local projects = config.projects or {}
  for k in pairs(projects) do
    local expanded_path = Path.new(k):expand()
    projects[expanded_path] = projects[k]
    if expanded_path ~= k then
      projects[k] = nil
    end
  end

  return config
end

function M.save()
  -- first refresh from disk everything but our project
  M.refresh_projects_b4update()

  Path:new(cache_config_path):write(vim.fn.json_encode(HarpoonConfig), 'w')
end

local function read_config(local_config)
  return vim.json.decode(Path:new(local_config):read())
end

-- 1. saved.  Where do we save?
function M.setup(config)
  if not config then
    config = {}
  end

  local ok, user_config = pcall(read_config, user_config_path)

  if not ok then
    user_config = {}
  end

  local ok2, cache_config = pcall(read_config, cache_config_path)

  if not ok2 then
    cache_config = {}
  end

  local complete_config = merge_tables({
    projects = {},
    global_settings = {
      ['save_on_toggle'] = false,
      ['save_on_change'] = true,
      ['excluded_filetypes'] = { 'harpoon' },
      ['mark_branch'] = false,
    },
  }, expand_dir(cache_config), expand_dir(user_config), expand_dir(config))

  -- There was this issue where the vim.loop.cwd() didn't have marks or term, but had
  -- an object for vim.loop.cwd()
  ensure_correct_config(complete_config)

  HarpoonConfig = complete_config
end

function M.get_global_settings()
  return HarpoonConfig.global_settings
end

-- refresh all projects from disk, except our current one
function M.refresh_projects_b4update()
  -- save current runtime version of our project config for merging back in later
  local cwd = mark_config_key()
  local current_p_config = {
    projects = {
      [cwd] = ensure_correct_config(HarpoonConfig).projects[cwd],
    },
  }

  -- erase all projects from global config, will be loaded back from disk
  HarpoonConfig.projects = nil

  -- this reads a stale version of our project but up-to-date versions
  -- of all other projects
  local ok2, c_config = pcall(read_config, cache_config_path)

  if not ok2 then
    c_config = { projects = {} }
  end
  -- don't override non-project config in HarpoonConfig later
  c_config = { projects = c_config.projects }

  -- erase our own project, will be merged in from current_p_config later
  c_config.projects[cwd] = nil

  local complete_config = merge_tables(HarpoonConfig, expand_dir(c_config), expand_dir(current_p_config))

  -- There was this issue where the vim.loop.cwd() didn't have marks or term, but had
  -- an object for vim.loop.cwd()
  ensure_correct_config(complete_config)

  HarpoonConfig = complete_config
end

---@return Harpoon.Marks
function M.get_mark_config()
  local config = ensure_correct_config(HarpoonConfig).projects[mark_config_key()].mark
  Snacks.debug.inspect(config)
  return config
end

---@return Harpoon.Menu
function M.get_menu_config()
  return HarpoonConfig.menu or {}
end

return M
