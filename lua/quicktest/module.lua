local api = vim.api
local notify = require("quicktest.notify")
local a = require("plenary.async")
local u = require("plenary.async.util")
local ui = require("quicktest.ui")

local M = {}

---@alias Adapter string | "auto"
---@alias WinMode 'popup' | 'split' | 'auto'
---@alias WinModeWithoutAuto 'popup' | 'split

---@class AdapterRunOpts
---@field additional_args string[]?

---@alias CmdData {type: 'stdout', raw: string, output: string?, decoded: any} | {type: 'stderr', raw: string, output: string?, decoded: any} | {type: 'exit', code: number}

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

---@class QuicktestConfig
---@field adapters QuicktestAdapter[]
---@field default_win_mode WinModeWithoutAuto
---@field use_baleia boolean

--- @type {id: number, started_at: number, pid: number?} | nil
local current_job = nil
local previous_run = nil

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

local baleia_pkg = nil
local get_baleia = function()
  if baleia_pkg then
    return baleia_pkg
  else
    baleia_pkg = require("baleia").setup({ name = "QuicktestOutputColors" })
    return baleia_pkg
  end
end

--- @param adapter QuicktestAdapter
--- @param params any
--- @param config QuicktestConfig
--- @param opts AdapterRunOpts
function M.run(adapter, params, config, opts)
  if current_job then
    if current_job.pid then
      vim.system({ "kill", tostring(current_job.pid) }):wait()
      current_job = nil
    else
      return notify.warn("Already running")
    end
  end

  local set_ansi_lines = vim.api.nvim_buf_set_lines
  if config.use_baleia then
    set_ansi_lines = get_baleia().buf_set_lines
  else
    --- @param buf integer
    --- @param start integer
    --- @param finish number
    --- @param strict_indexing boolean
    --- @param replacements string[]
    set_ansi_lines = function(buf, start, finish, strict_indexing, replacements)
      local new_lines = {}
      for i, line in ipairs(replacements) do
        new_lines[i] = string.gsub(line, "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
      end
      vim.api.nvim_buf_set_lines(buf, start, finish, strict_indexing, new_lines)
    end
  end

  --- @type {id: number, started_at: number, pid: number?, exit_code: number?}
  local job = { id = math.random(10000000000000000), started_at = vim.uv.now() }
  current_job = job
  previous_run = { adapter = adapter, params = params, opts = opts }

  local is_running = function()
    return current_job and job.id == current_job.id
  end

  local print_status = function()
    for _, buf in ipairs(ui.buffers) do
      local line_count = vim.api.nvim_buf_line_count(buf)

      local passedTime = vim.loop.now() - job.started_at
      local time_display = string.format("%.2f", passedTime / 1000) .. "s"

      if job.exit_code == nil then
        vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, {
          "Running " .. time_display,
        })
        vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticInfo", line_count - 1, 0, -1)
      else
        if job.exit_code ~= 0 then
          vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { "Failed " .. time_display })

          vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", line_count - 1, 0, -1)
        else
          vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { "Passed " .. time_display })

          vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticOk", line_count - 1, 0, -1)
        end
      end
    end
  end

  for _, buf in ipairs(ui.buffers) do
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

    ui.scroll_down(buf)
  end

  ---@diagnostic disable-next-line: missing-parameter
  a.run(function()
    local sender, receiver = a.control.channel.mpsc()
    local pid = adapter.run(params, function(data)
      sender.send(data)
    end)
    job.pid = pid

    if adapter.title then
      local title = adapter.title(params)
      for _, buf in ipairs(ui.buffers) do
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          title,
          "",
          "",
          "",
        })

        ui.scroll_down(buf)
      end
    else
      for _, buf in ipairs(ui.buffers) do
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "",
          "",
        })
      end
    end

    ---@diagnostic disable-next-line: missing-parameter
    a.run(function()
      while is_running() do
        print_status()
        u.sleep(100)
      end
    end)

    local results = {}
    while is_running() do
      local result = receiver.recv()
      table.insert(results, result)

      u.scheduler()

      if not is_running() then
        return
      end

      if result.type == "exit" then
        job.exit_code = result.code

        current_job = nil
        if adapter.after_run then
          adapter.after_run(params, results)
        end
      end

      for _, buf in ipairs(ui.buffers) do
        local should_scroll = ui.should_continue_scroll(buf)

        if result.type == "stdout" then
          if result.output then
            local line_count = vim.api.nvim_buf_line_count(buf)
            local lines = vim.split(result.output, "\n")

            table.insert(lines, "")
            table.insert(lines, "")

            set_ansi_lines(buf, line_count - 2, -1, false, lines)
          end
        end

        if result.type == "stderr" then
          local line_count = vim.api.nvim_buf_line_count(buf)
          local lines = vim.split(result.output, "\n")

          table.insert(lines, "")
          table.insert(lines, "")
          if #lines > 0 then
            set_ansi_lines(buf, line_count - 2, -1, false, lines)

            for i = 0, #lines - 1 do
              vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", line_count - 2 + i, 0, -1)
            end
          end
        end

        if should_scroll then
          ui.scroll_down(buf)
        end
      end

      print_status()
    end
  end)
end

--- @param config QuicktestConfig
--- @param type 'line' | 'file' | 'dir' | 'all'
--- @param mode WinMode
--- @param adapter_name Adapter
--- @param opts AdapterRunOpts
function M.prepare_and_run(config, type, mode, adapter_name, opts)
  local win_mode = mode == "auto" and M.current_win_mode(config.default_win_mode) or mode --[[@as WinModeWithoutAuto]]
  local current_buffer = api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win() -- Get the current active window
  local cursor_pos = vim.api.nvim_win_get_cursor(win) -- Get the cursor position in the window

  --- @type QuicktestAdapter
  local adapter = adapter_name == "auto" and get_adapter(config, type)
    or get_adapter_by_name(config.adapters, adapter_name)

  if not adapter then
    return notify.warn("Failed to test: no suitable adapter found.")
  end

  local method = adapter["build_" .. type .. "_run_params"]

  if not method then
    return notify.warn("Failed to test: adapter '" .. adapter.name .. "' does not support '" .. type .. "' run.")
  end

  local params, error = method(current_buffer, cursor_pos, opts)

  if error ~= nil and error ~= "" then
    return notify.warn("Failed to test: " .. error .. ".")
  end

  M.try_open_win(win_mode)

  M.run(adapter, params, config, opts)
end

--- @param config QuicktestConfig
--- @param mode WinMode?
function M.run_previous(config, mode)
  local win_mode = mode == "auto" and M.current_win_mode(config.default_win_mode) or mode --[[@as WinModeWithoutAuto]]

  M.try_open_win(win_mode)

  if not previous_run then
    return notify.warn("No previous run")
  end

  M.run(previous_run.adapter, previous_run.params, config, previous_run.opts)
end

function M.kill_current_run()
  if current_job then
    local job = current_job
    vim.system({ "kill", tostring(current_job.pid) }):wait()
    current_job = nil

    for _, buf in ipairs(ui.buffers) do
      local line_count = vim.api.nvim_buf_line_count(buf)

      local passedTime = vim.loop.now() - job.started_at
      local time_display = string.format("%.2f", passedTime / 1000) .. "s"

      vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { "Cancelled after " .. time_display })
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticWarn", line_count - 1, 0, -1)
    end
  end
end

--- @param default_mode WinModeWithoutAuto
--- @return WinModeWithoutAuto
function M.current_win_mode(default_mode)
  if ui.is_split_opened then
    return "split"
  elseif ui.is_popup_opened then
    return "popup"
  else
    return default_mode
  end
end

---@param mode WinModeWithoutAuto
function M.try_open_win(mode)
  ui.try_open_win(mode)
  for _, buf in ipairs(ui.buffers) do
    ui.scroll_down(buf)
  end
end

---@param mode WinModeWithoutAuto
function M.try_close_win(mode)
  ui.try_close_win(mode)
end

---@param mode WinModeWithoutAuto
function M.toggle_win(mode)
  if mode == "split" then
    if ui.is_split_opened then
      ui.try_close_win("split")
    else
      ui.try_open_win("split")

      for _, buf in ipairs(ui.buffers) do
        ui.scroll_down(buf)
      end
    end
  else
    if ui.is_popup_opened then
      ui.try_close_win("popup")
    else
      ui.try_open_win("popup")

      for _, buf in ipairs(ui.buffers) do
        ui.scroll_down(buf)
      end
    end
  end
end

return M
