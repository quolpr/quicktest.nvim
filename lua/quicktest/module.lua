local api = vim.api
local notify = require("quicktest.notify")
local a = require("plenary.async")
local u = require("plenary.async.util")
local ui = require("quicktest.ui")
local baleia = require("baleia").setup({ name = "QuicktestOutputColors" })

local M = {}

---@alias WinMode 'popup' | 'split'

---@alias CmdData {type: 'stdout', raw: string, output: string?, decoded: any} | {type: 'stderr', raw: string, output: string?, decoded: any} | {type: 'exit', code: number}

---@class QuicktestPlugin
---@field name string
---@field build_line_run_params fun(bufnr: integer, cursor_pos: integer[]): any
---@field build_file_run_params fun(bufnr: integer, cursor_pos: integer[]): any
---@field can_run fun(params: any)
---@field run fun(params: GoRunParams, send: fun(data: CmdData)): number
---@field after_run fun(params: GoRunParams, results: CmdData)?
---@field title fun(params: GoRunParams): string
---@field is_enabled fun(bufnr): boolean

---@class QuicktestConfig
---@field plugins QuicktestPlugin[]

--- @type {id: number, pid: number?} | nil
local current_job = nil
local previous_run = nil

--- @param config QuicktestConfig
local function getPlugin(config)
  local current_buffer = api.nvim_get_current_buf()

  --- @type QuicktestPlugin
  local plugin

  for _, plug in ipairs(config.plugins) do
    if plug.is_enabled(current_buffer) then
      plugin = plug
      break
    end
  end

  return plugin
end

--- @param plugin QuicktestPlugin
--- @param params any
function M.run(plugin, params)
  if current_job then
    if current_job.pid then
      vim.system({ "kill", tostring(current_job.pid) }):wait()
      current_job = nil
    else
      return notify.warn("Already running")
    end
  end

  --- @type {id: number, pid: number?, exit_code: number?}
  local job = { id = math.random(10000000000000000) }
  current_job = job
  previous_run = { plugin = plugin, params = params }
  local current_time = vim.uv.now()

  local is_running = function()
    return current_job and job.id == current_job.id
  end

  local print_status = function()
    for _, buf in ipairs(ui.buffers) do
      local line_count = vim.api.nvim_buf_line_count(buf)

      local passedTime = vim.loop.now() - current_time
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
    local pid = plugin.run(params, function(data)
      sender.send(data)
    end)
    job.pid = pid

    local title = plugin.title(params)
    for _, buf in ipairs(ui.buffers) do
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        title,
        "",
        "",
        "",
      })

      ui.scroll_down(buf)
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

      for _, buf in ipairs(ui.buffers) do
        local should_scroll = ui.should_continue_scroll(buf)
        if result.type == "exit" then
          job.exit_code = result.code

          print_status()
          current_job = nil
          plugin.after_run(params, results)
        end

        if result.type == "stdout" then
          if result.output then
            local line_count = vim.api.nvim_buf_line_count(buf)
            local lines = vim.split(result.output, "\n")

            table.insert(lines, "")
            table.insert(lines, "")

            baleia.buf_set_lines(buf, line_count - 2, -1, false, lines)

            print_status()
          end
        end

        if result.type == "stderr" then
          local line_count = vim.api.nvim_buf_line_count(buf)
          local lines = vim.split(result.output, "\n")

          table.insert(lines, "")
          table.insert(lines, "")
          if #lines > 0 then
            vim.api.nvim_buf_set_lines(buf, line_count - 2, -1, false, lines)

            for i = 0, #lines - 1 do
              vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", line_count - 2 + i, 0, -1)
            end

            print_status()
          end
        end

        if should_scroll then
          ui.scroll_down(buf)
        end
      end
    end
  end)
end

--- @param config QuicktestConfig
--- @param mode WinMode?
function M.run_line(config, mode)
  mode = mode or M.current_win_mode()
  local current_buffer = api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win() -- Get the current active window
  local cursor_pos = vim.api.nvim_win_get_cursor(win) -- Get the cursor position in the window

  --- @type QuicktestPlugin
  local plugin = getPlugin(config)

  if not plugin then
    return notify.warn("Can't test this file - no plugin found")
  end

  M.try_open_win(mode)

  local params = plugin.build_line_run_params(current_buffer, cursor_pos)

  if not plugin.can_run(params) then
    return notify.warn("No tests to run")
  end

  M.run(plugin, params)
end

--- @param config QuicktestConfig
--- @param mode WinMode?
function M.run_file(config, mode)
  mode = mode or M.current_win_mode()
  local current_buffer = api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win() -- Get the current active window
  local cursor_pos = vim.api.nvim_win_get_cursor(win) -- Get the cursor position in the window

  --- @type QuicktestPlugin
  local plugin = getPlugin(config)

  if not plugin then
    return notify.warn("No plugin found")
  end

  M.try_open_win(mode)

  local params = plugin.build_file_run_params(current_buffer, cursor_pos)

  if not plugin.can_run(params) then
    return notify.warn("No tests to run")
  end

  M.run(plugin, params)
end

--- @param mode WinMode?
function M.run_previous(mode)
  mode = mode or M.current_win_mode()

  M.try_open_win(mode)

  if not previous_run then
    return notify.warn("No previous run")
  end

  M.run(previous_run.plugin, previous_run.params)
end

function M.current_win_mode()
  if ui.is_split_opened then
    return "split"
  elseif ui.is_popup_opened then
    return "popup"
  else
    return "popup"
  end
end

function M.try_open_win(mode)
  ui.try_open_win(mode)
  for _, buf in ipairs(ui.buffers) do
    ui.scroll_down(buf)
  end
end

function M.try_close_win(mode)
  ui.try_close_win(mode)
end

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

-- if baleia == nil then
--   baleia = require('baleia').setup {
--     async = false,
--   }
-- end

return M
