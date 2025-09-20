local api = vim.api
local notify = require("quicktest.notify")
local a = require("plenary.async")
local u = require("plenary.async.util")
local ui = require("quicktest.ui")
local colorized_printer = require("quicktest.colored_printer")
local p = require("plenary.path")

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
---@field use_builtin_colorizer boolean

---@alias JobStatus 'running' | 'finished' | 'canceled'
---@alias CmdJob {id: number, started_at: number, finished_at?: number, pid: number?, status: JobStatus, exit_code?: number}
---@type CmdJob | nil
local current_job = nil
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

local status_ns = vim.api.nvim_create_namespace("quicktest_status")
local stderr_ns = vim.api.nvim_create_namespace("quicktest_stderr")

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

  --- @param buf integer
  --- @param start integer
  --- @param finish number
  --- @param strict_indexing boolean
  --- @param replacements string[]
  local set_ansi_lines = function(buf, start, finish, strict_indexing, replacements)
    local new_lines = {}
    for i, line in ipairs(replacements) do
      new_lines[i] = string.gsub(line, "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
    end
    vim.api.nvim_buf_set_lines(buf, start, finish, strict_indexing, new_lines)
  end

  local printer = colorized_printer.new()

  --- @type CmdJob
  local job = { id = math.random(10000000000000000), started_at = vim.uv.now(), status = "running" }
  current_job = job

  local is_running = function()
    return current_job and job.id == current_job.id and current_job.status == "running"
  end

  local print_buf_status = function(buf, line_count)
    local passedTime = vim.loop.now() - job.started_at
    if job.finished_at then
      passedTime = job.finished_at - job.started_at
    end

    local time_display = string.format("%.2f", passedTime / 1000) .. "s"

    vim.api.nvim_buf_clear_namespace(buf, status_ns, 0, -1)

    local hl_group = ""
    local line = ""
    if job.exit_code == nil and job.status == "running" then
      line = "Running " .. time_display
      hl_group = "DiagnosticInfo"
    else
      if job.status == "canceled" then
        line = "Canceled " .. time_display
        hl_group = "DiagnosticWarn"
      elseif job.exit_code ~= 0 then
        line = "Failed " .. time_display
        hl_group = "DiagnosticError"
      else
        line = "Passed " .. time_display
        hl_group = "DiagnosticOk"
      end
    end

    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, {
      line,
    })
    vim.api.nvim_buf_set_extmark(buf, status_ns, line_count - 1, 0, {
      end_col = line:len(),
      hl_group = hl_group,
    })
  end
  local print_status = function()
    for _, buf in ipairs(ui.get_buffers()) do
      local line_count = vim.api.nvim_buf_line_count(buf)

      print_buf_status(buf, line_count)
    end
  end

  for _, buf in ipairs(ui.get_buffers()) do
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

    ui.scroll_down(buf)
  end

  local runLoop = function()
    local sender, receiver = a.control.channel.mpsc()
    local pid = adapter.run(params, function(data)
      sender.send(data)
    end)
    job.pid = pid

    if adapter.title then
      local title = adapter.title(params)
      for _, buf in ipairs(ui.get_buffers()) do
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          title,
          "",
          "",
          "",
        })

        ui.scroll_down(buf)
      end
    else
      for _, buf in ipairs(ui.get_buffers()) do
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "",
          "",
        })
      end
    end

    local results = {}
    local lines_buffer = {}
    local errored_lines = {}

    local run_printer = function()
      local print_lines = function()
        local new_lines_count = #lines_buffer

        if new_lines_count > 0 then
          table.insert(lines_buffer, "")
          table.insert(lines_buffer, "")

          for _, buf in ipairs(ui.get_buffers()) do
            local lines_count = vim.api.nvim_buf_line_count(buf)
            local should_scroll = ui.should_continue_scroll(buf, lines_count - 2)

            if config.use_builtin_colorizer then
              printer:set_next_lines(lines_buffer, buf, lines_count - 2)
            else
              set_ansi_lines(buf, lines_count - 2, -1, false, lines_buffer)
            end

            for i, _ in ipairs(errored_lines) do
              vim.highlight.range(
                buf,
                stderr_ns,
                "DiagnosticError",
                { i + lines_count - 2, 0 },
                { i + lines_count - 2, -1 }
              )
            end

            print_buf_status(buf, lines_count + new_lines_count)
            if should_scroll then
              ui.scroll_down(buf)
            end
          end

          lines_buffer = {}
          errored_lines = {}
        end
      end

      while is_running() do
        u.scheduler()

        print_lines()
        print_status()

        vim.cmd("redraw")
        u.sleep(100)
      end

      -- In case new job is started and we don't want to print the previous one
      if job.id == current_job.id then
        u.scheduler()
        print_lines()
        print_status()
      end
    end

    ---@diagnostic disable-next-line: missing-parameter
    a.run(function()
      xpcall(run_printer, function(err)
        print("Error in async job:", err)
        print("Stack trace:", debug.traceback())

        notify.error("Test run failed: " .. err)
      end)
    end)

    while is_running() do
      local result = receiver.recv()
      table.insert(results, result)

      if not is_running() then
        return
      end

      if result.type == "exit" then
        job.exit_code = result.code
        job.finished_at = vim.uv.now()
        job.status = "finished"

        if adapter.after_run then
          u.scheduler()
          adapter.after_run(params, results)
        end
      end

      if result.type == "stdout" or result.type == "stderr" then
        if result.output then
          local lines = vim.split(result.output, "\n")
          local new_lines_count = #lines

          if new_lines_count > 0 then
            local buffer_size = #lines_buffer
            for i, line in ipairs(lines) do
              table.insert(lines_buffer, line)

              if result.type == "stderr" then
                errored_lines[buffer_size + i] = true
              end
            end
          end
        end
      end
    end
  end

  ---@diagnostic disable-next-line: missing-parameter
  a.run(function()
    xpcall(runLoop, function(err)
      print("Error in async job:", err)
      print("Stack trace:", debug.traceback())

      notify.error("Test run failed: " .. err)
    end)
  end)
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
function M.prepare_and_run(config, type, mode, adapter_name, opts)
  local win_mode = mode == "auto" and M.current_win_mode(config.default_win_mode) or mode --[[@as WinModeWithoutAuto]]
  local current_buffer = api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win() -- Get the current active window
  local cursor_pos = vim.api.nvim_win_get_cursor(win) -- Get the cursor position in the window

  local adapter, params, error = get_adapter_and_params(config, type, adapter_name, current_buffer, cursor_pos, opts)
  if error ~= nil then
    return notify.warn(error)
  end
  if adapter == nil or params == nil then
    return notify.warn("Failed to test: no suitable adapter found.")
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

  M.try_open_win(win_mode)
  M.run(adapter, params, config, opts)
end

--- @param config QuicktestConfig
--- @param mode WinMode?
function M.run_previous(config, mode)
  local win_mode = mode == "auto" and M.current_win_mode(config.default_win_mode) or mode --[[@as WinModeWithoutAuto]]

  if not previous_run then
    previous_run = load_previous_run()
  end

  local cwd = vim.fn.getcwd()
  local current_run = previous_run[cwd]

  if not current_run then
    return notify.warn("No previous run for this project")
  end

  local bufnr = get_buf_by_name(current_run.bufname)
  local is_loaded = false
  if bufnr ~= nil then
    is_loaded = vim.api.nvim_buf_is_loaded(bufnr)
  end

  if not is_loaded then
    -- If the buffer doesn't exist, try to open the file
    bufnr = vim.fn.bufadd(current_run.bufname)
    if bufnr == 0 then
      return notify.warn("Failed to open previous run file: " .. current_run.bufname)
    end

    -- Ensure the buffer is listed
    vim.bo[bufnr].buflisted = true

    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! e!") -- Try to edit the buffer in place to force load it
    end)
  end

  if vim.bo[bufnr].filetype == "" then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("filetype detect")
    end)
  end

  local adapter, params, error =
    get_adapter_and_params(config, current_run.type, current_run.adapter_name, bufnr, current_run.cursor_pos, {})
  if error ~= nil then
    return notify.warn(error)
  end
  if adapter == nil or params == nil then
    return notify.warn("Failed to test: no suitable adapter found.")
  end

  M.try_open_win(win_mode)
  M.run(adapter, params, config, {})
end

function M.kill_current_run()
  if current_job then
    local job = current_job
    vim.system({ "kill", tostring(current_job.pid) }):wait()

    job.status = "canceled"
    job.finished_at = vim.uv.now()
  end
end

--- @param default_mode WinModeWithoutAuto
--- @return WinModeWithoutAuto
function M.current_win_mode(default_mode)
  if ui.is_split_opened() then
    return "split"
  elseif ui.is_popup_opened() then
    return "popup"
  else
    return default_mode
  end
end

---@param mode WinModeWithoutAuto
function M.try_open_win(mode)
  ui.try_open_win(mode)
  for _, buf in ipairs(ui.get_buffers()) do
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
    if ui.is_split_opened() then
      ui.try_close_win("split")
    else
      ui.try_open_win("split")

      for _, buf in ipairs(ui.get_buffers()) do
        ui.scroll_down(buf)
      end
    end
  else
    if ui.is_popup_opened() then
      ui.try_close_win("popup")
    else
      ui.try_open_win("popup")

      for _, buf in ipairs(ui.get_buffers()) do
        ui.scroll_down(buf)
      end
    end
  end
end

return M
