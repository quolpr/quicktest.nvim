local ui = require("quicktest.ui")
local colorized_printer = require("quicktest.colored_printer")
local notify = require("quicktest.notify")
local a = require("plenary.async")
local u = require("plenary.async.util")

local M = {
  name = "default"
}

-- Module-level current job tracking (shared with kill function)
local current_job = nil

-- Expose kill function for external access
M.kill_current_run = function()
  if current_job and current_job.pid then
    local job = current_job
    vim.system({ "kill", tostring(current_job.pid) }):wait()
    current_job = nil

    for _, buf in ipairs(ui.get_buffers()) do
      local line_count = vim.api.nvim_buf_line_count(buf)
      local passedTime = vim.loop.now() - job.started_at
      local time_display = string.format("%.2f", passedTime / 1000) .. "s"

      vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { "Cancelled after " .. time_display })
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticWarn", line_count - 1, 0, -1)
    end
  end
end

M.is_available = function()
  return true
end

M.run = function(adapter, params, config, opts)
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

  --- @type {id: number, started_at: number, pid: number?, exit_code: number?}
  local job = { id = math.random(10000000000000000), started_at = vim.uv.now() }
  current_job = job

  local is_running = function()
    return current_job and job.id == current_job.id
  end

  local print_status = function()
    for _, buf in ipairs(ui.get_buffers()) do
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

  for _, buf in ipairs(ui.get_buffers()) do
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
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

    ---@diagnostic disable-next-line: missing-parameter
    a.run(function()
      while is_running() do
        print_status()
        u.sleep(100)
      end
    end)

    local last_update_time = 0
    local update_interval = 100 -- ms

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

      for _, buf in ipairs(ui.get_buffers()) do
        local should_scroll = ui.should_continue_scroll(buf)

        if result.type == "stdout" then
          if result.output then
            local lines = vim.split(result.output, "\n")

            table.insert(lines, "")
            table.insert(lines, "")

            if config.use_builtin_colorizer then
              printer:set_next_lines(lines, buf, 2)
            else
              local line_count = vim.api.nvim_buf_line_count(buf)
              set_ansi_lines(buf, line_count - 2, -1, false, lines)
            end
          end
        end

        if result.type == "stderr" then
          if result.output then
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
        end

        local current_time = vim.loop.now()
        if (current_time - last_update_time) > update_interval then
          u.scheduler(function()
            vim.cmd("redraw")
          end)
          last_update_time = current_time
        end

        if should_scroll then
          ui.scroll_down(buf)
        end
      end

      print_status()
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

  -- Return strategy result interface
  return {
    is_complete = function()
      return current_job == nil
    end,
    output_stream = function()
      return function()
        return nil
      end
    end,
    output = function()
      return ""
    end,
    stop = function()
      M.kill_current_run()
    end,
    result = function()
      while current_job do
        vim.wait(100)
      end
      return job.exit_code or -1
    end,
  }
end

return M

