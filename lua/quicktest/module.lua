local api = vim.api
local notify = require("quicktest.notify")
local a = require("plenary.async")
local u = require("plenary.async.util")
local ui = require("quicktest.ui")
local p = require("plenary.path")
local strategies = require("quicktest.strategies")

local M = {}

---@alias Adapter string | "auto"
---@alias WinMode 'popup' | 'split' | 'auto'
---@alias WinModeWithoutAuto 'popup' | 'split

---@class AdapterRunOpts
---@field additional_args string[]?
---@field strategy ('default' | 'dap')?

---@alias CmdData {type: 'stdout', raw: string, output: string?, decoded: any} | {type: 'stderr', raw: string, output: string?, decoded: any} | {type: 'exit', code: number} | {type: 'test_result', test_name: string, status: 'passed' | 'failed', location: string?}

---@alias RunType 'line' | 'file' | 'dir' | 'all'

---@class QuicktestAdapter
---@field name string
---@field build_line_run_params fun(bufnr: integer, cursor_pos: integer[], opts: AdapterRunOpts): any
---@field build_file_run_params fun(bufnr: integer, cursor_pos: integer[], opts: AdapterRunOpts): any
---@field build_dir_run_params fun(bufnr: integer, cursor_pos: integer[], opts: AdapterRunOpts): any
---@field build_all_run_params fun(bufnr: integer, cursor_pos: integer[], opts: AdapterRunOpts): any
---@field run fun(params: any, send: fun(data: CmdData)): number
---@field after_run fun(params: any, results: CmdData)?
---@field title fun(params: any): string
---@field is_enabled fun(bufnr: number, type: RunType): boolean
---@field build_dap_config? fun(bufnr: integer, params: any): table

---@class QuicktestConfig
---@field adapters QuicktestAdapter[]
---@field default_win_mode WinModeWithoutAuto
---@field use_builtin_colorizer boolean
---@field strategy? 'default' | 'dap' | fun(adapter: QuicktestAdapter): string

--- @type {[string]: {type: string, adapter_name: string, bufname: string, cursor_pos: integer[]}} | nil
local previous_run = nil

local function load_previous_run()
  local config_path = p:new(vim.fn.stdpath("data"), "quicktest_previous_runs.json")

  if config_path:exists() then
    local content = config_path:read()
    if content and content ~= "" then
      local ok, data = pcall(vim.json.decode, content)
      if ok then
        return data
      end
    end
  end
  return {}
end

local function save_previous_run()
  if previous_run then
    ---@diagnostic disable-next-line: missing-parameter
    a.run(function()
      local config_path = p:new(vim.fn.stdpath("data"), "quicktest_previous_runs.json")
      local current_data = load_previous_run()

      -- Merge the new previous_run data with existing data
      for cwd, run_data in pairs(previous_run) do
        current_data[cwd] = run_data
      end

      local json_str = vim.json.encode(current_data)
      config_path:write(json_str, "w")
    end)
  end
end
local function get_buf_by_name(name)
  local bufs = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(bufs) do
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname:match(name .. "$") then
      return bufnr
    end
  end

  return nil
end

--- @param config QuicktestConfig
--- @param type RunType
--- @return QuicktestAdapter
local function get_adapter(config, type)
  local current_buffer = api.nvim_get_current_buf()

  --- @type QuicktestAdapter
  local adapter

  for _, plug in ipairs(config.adapters) do
    if plug.is_enabled(current_buffer, type) then
      adapter = plug
      break
    end
  end

  return adapter
end

--- @param adapters QuicktestAdapter[]
--- @param name string
--- @return QuicktestAdapter
local function get_adapter_by_name(adapters, name)
  local adapter

  for _, plug in ipairs(adapters) do
    if plug.name == name then
      adapter = plug
      break
    end
  end

  return adapter
end

--- @param config QuicktestConfig
--- @param adapter QuicktestAdapter
--- @param opts AdapterRunOpts?
--- @return string
local function get_strategy_name(config, adapter, opts)
  local available_strategies = strategies.get_available()

  local function validate_and_fallback(strategy_name, fallback)
    if strategy_name and not available_strategies[strategy_name] then
      local available_names = vim.tbl_keys(available_strategies)
      table.sort(available_names)
      vim.notify(
        "Invalid strategy: " ..
        strategy_name .. ". Available: " .. table.concat(available_names, ", ") .. ". Using '" .. fallback .. "'.",
        vim.log.levels.WARN)
      return fallback
    end
    return strategy_name or fallback
  end

  -- Priority: opts > config > default
  if opts and opts.strategy then
    return validate_and_fallback(opts.strategy, "default")
  end

  if not config.strategy then
    return "default"
  end

  if type(config.strategy) == "function" then
    local result = config.strategy(adapter)
    return validate_and_fallback(result, "default")
  end

  return validate_and_fallback(config.strategy, "default")
end

--- @param adapter QuicktestAdapter
--- @param params any
--- @param mode WinMode?
--- @param config QuicktestConfig
--- @param opts AdapterRunOpts
--- @return QuicktestStrategyResult?
function M.run(adapter, params, mode, config, opts)
  local strategy_name = get_strategy_name(config, adapter, opts)
  local strategy = strategies.get(strategy_name)

  if not strategy then
    notify.error("Strategy '" .. strategy_name .. "' not found")
    return nil
  end

  if not strategy.is_available() then
    notify.error("Strategy '" .. strategy_name .. "' is not available")
    return nil
  end

  -- Only open UI window for non-DAP strategies
  if strategy_name ~= "dap" then
    local win_mode = mode == "auto" and M.current_win_mode(config.default_win_mode) or mode --[[@as WinModeWithoutAuto]]
    local panel = ui.get("panel")
    if panel then
      panel.try_open_win(win_mode)
    end
  end

  return strategy.run(adapter, params, config, opts)
end

local function get_adapter_and_params(config, type, adapter_name, current_buffer, cursor_pos, opts)
  --- @type QuicktestAdapter
  local adapter = adapter_name == "auto" and get_adapter(config, type)
      or get_adapter_by_name(config.adapters, adapter_name)

  if not adapter then
    return nil, nil, "Failed to test: no suitable adapter found."
  end

  local method = adapter["build_" .. type .. "_run_params"]

  if not method then
    return nil, nil, "Failed to test: adapter '" .. adapter.name .. "' does not support '" .. type .. "' run."
  end

  local params, error = method(current_buffer, cursor_pos, opts)
  if error ~= nil and error ~= "" then
    return nil, nil, "Failed to test: " .. error .. "."
  end

  return adapter, params, nil
end

--- @param config QuicktestConfig
--- @param type 'line' | 'file' | 'dir' | 'all'
--- @param mode WinMode
--- @param adapter_name Adapter
--- @param opts AdapterRunOpts
--- @return QuicktestStrategyResult?
function M.prepare_and_run(config, type, mode, adapter_name, opts)
  local current_buffer = api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()          -- Get the current active window
  local cursor_pos = vim.api.nvim_win_get_cursor(win) -- Get the cursor position in the window

  local adapter, params, error = get_adapter_and_params(config, type, adapter_name, current_buffer, cursor_pos, opts)
  if error ~= nil then
    notify.warn(error)
    return nil
  end
  if adapter == nil or params == nil then
    notify.warn("Failed to test: no suitable adapter found.")
    return nil
  end

  local buf_name = api.nvim_buf_get_name(current_buffer)
  if buf_name ~= "" then
    local cwd = vim.fn.getcwd()
    if not previous_run then
      previous_run = load_previous_run()
    end

    previous_run[cwd] = {
      type = type,
      adapter_name = adapter.name,
      bufname = buf_name,
      cursor_pos = cursor_pos,
    }
    save_previous_run()
  end

  return M.run(adapter, params, mode, config, opts)
end

--- @param config QuicktestConfig
--- @param mode WinMode?
--- @return QuicktestStrategyResult?
function M.run_previous(config, mode)
  if not previous_run then
    previous_run = load_previous_run()
  end

  local cwd = vim.fn.getcwd()
  local current_run = previous_run[cwd]

  if not current_run then
    notify.warn("No previous run for this project")
    return nil
  end

  local bufnr = get_buf_by_name(current_run.bufname)
  if bufnr == nil then
    -- If the buffer doesn't exist, try to open the file
    bufnr = vim.fn.bufadd(current_run.bufname)
    if bufnr == 0 then
      notify.warn("Failed to open previous run file: " .. current_run.bufname)
      return nil
    end

    -- Ensure the buffer is loaded
    vim.bo[bufnr].buflisted = true
  end

  if vim.bo[bufnr].filetype == "" then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("filetype detect")
    end)
  end

  local adapter, params, error =
      get_adapter_and_params(config, current_run.type, current_run.adapter_name, bufnr, current_run.cursor_pos, {})
  if error ~= nil then
    notify.warn(error)
    return nil
  end
  if adapter == nil or params == nil then
    notify.warn("Failed to test: no suitable adapter found.")
    return nil
  end

  return M.run(adapter, params, mode, config, {})
end

function M.kill_current_run()
  -- Delegate to the default strategy's kill function
  local default_strategy = strategies.get("default")
  if default_strategy and default_strategy.kill_current_run then
    default_strategy.kill_current_run()
  end
end

--- @param default_mode WinModeWithoutAuto
--- @return WinModeWithoutAuto
function M.current_win_mode(default_mode)
  local panel = ui.get("panel")
  if panel then
    if panel.is_split_opened() then
      return "split"
    elseif panel.is_popup_opened() then
      return "popup"
    else
      return default_mode
    end
  end
  return default_mode
end

---@param mode WinModeWithoutAuto
function M.try_open_win(mode)
  local panel = ui.get("panel")
  if panel then
    panel.try_open_win(mode)
    for _, buf in ipairs(panel.get_buffers()) do
      panel.scroll_down(buf)
    end
  end
end

---@param mode WinModeWithoutAuto
function M.try_close_win(mode)
  local panel = ui.get("panel")
  if panel then
    panel.try_close_win(mode)
  end
end

---@param mode WinModeWithoutAuto
function M.toggle_win(mode)
  local panel = ui.get("panel")
  if panel then
    local is_open = false
    if mode == "split" then
      is_open = panel.is_split_opened()
    else
      is_open = panel.is_popup_opened()
    end

    if is_open then
      M.try_close_win(mode)
    else
      M.try_open_win(mode)
    end
  end
end

return M
