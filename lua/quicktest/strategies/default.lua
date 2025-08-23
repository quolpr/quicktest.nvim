local storage = require("quicktest.storage")
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

    local passedTime = vim.loop.now() - job.started_at
    local time_display = string.format("%.2f", passedTime / 1000) .. "s"
    
    storage.test_output("status", "Cancelled after " .. time_display)
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

  -- Clear storage for new run
  storage.clear()

  --- @type {id: number, started_at: number, pid: number?, exit_code: number?}
  local job = { id = math.random(10000000000000000), started_at = vim.uv.now() }
  current_job = job

  local is_running = function()
    return current_job and job.id == current_job.id
  end

  local runLoop = function()
    local sender, receiver = a.control.channel.mpsc()
    local pid = adapter.run(params, function(data)
      sender.send(data)
    end)
    job.pid = pid

    -- Start test event
    local test_name = "Test"
    local test_location = ""
    
    if adapter.title then
      test_name = adapter.title(params)
    end
    
    if params and params.bufnr then
      test_location = vim.api.nvim_buf_get_name(params.bufnr)
      if params.line_number then
        test_location = test_location .. ":" .. params.line_number
      end
    end
    
    storage.test_started(test_name, test_location)

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
        
        -- Emit test finished event
        local status = result.code == 0 and "passed" or "failed"
        local duration = vim.uv.now() - job.started_at
        storage.test_finished(test_name, status, duration)
        
        if adapter.after_run then
          adapter.after_run(params, results)
        end
      elseif result.type == "stdout" and result.output then
        storage.test_output("stdout", result.output)
      elseif result.type == "stderr" and result.output then
        storage.test_output("stderr", result.output)
      elseif result.type == "test_result" then
        -- Handle individual test results from adapter
        -- First ensure this test exists in storage (create if needed)
        storage.test_started(result.test_name, result.location or "")
        -- Then mark it as finished
        storage.test_finished(result.test_name, result.status, nil, result.location)
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
