local M = {
  name = "dap"
}

M.is_available = function()
  local ok, dap = pcall(require, "dap")
  return ok and dap ~= nil
end

---@param adapter QuicktestAdapter
---@param params any
---@param config QuicktestConfig
---@param opts AdapterRunOpts
---@return QuicktestStrategyResult
M.run = function(adapter, params, config, opts)
  if not adapter.build_dap_config then
    error("Adapter does not support DAP strategy - missing build_dap_config method")
  end

  local dap = require("dap")
  
  local handler_id = "quicktest_" .. vim.fn.localtime()
  local output_data = {}
  local is_finished = false
  local result_code = nil
  
  local output_path = vim.fn.tempname()
  local output_fd = nil
  
  local function write_output(data)
    table.insert(output_data, data)
    if output_fd then
      local write_err, _ = vim.uv.fs_write(output_fd, data)
      if write_err then
        vim.notify("Failed to write DAP output: " .. write_err, vim.log.levels.WARN)
      end
    end
  end

  -- Try to open output file, but don't fail if it doesn't work
  local open_err
  open_err, output_fd = vim.uv.fs_open(output_path, "w", 438)
  if open_err then
    vim.notify("Failed to create DAP output file: " .. open_err, vim.log.levels.WARN)
    output_fd = nil
  end

  local dap_config = adapter.build_dap_config(params.bufnr, params)
  
  -- Get filetype for DAP configuration
  local test_bufnr = vim.fn.bufnr(params.bufnr)
  local filetype = vim.api.nvim_buf_get_option(test_bufnr, "filetype")

  dap.run(vim.tbl_extend("keep", dap_config, { env = dap_config.env, cwd = dap_config.cwd }), {
    filetype = filetype,
    before = function(cfg)
      dap.listeners.after.event_output[handler_id] = function(_, body)
        if vim.tbl_contains({ "stdout", "stderr" }, body.category) then
          write_output(body.output)
        end
      end
      
      dap.listeners.after.event_exited[handler_id] = function(_, info)
        result_code = info.exitCode
        is_finished = true
        if output_fd then
          vim.uv.fs_close(output_fd)
        end
      end

      return cfg
    end,
    after = function()
      local received_exit = result_code ~= nil
      if not received_exit then
        result_code = 0
        is_finished = true
        if output_fd then
          vim.uv.fs_close(output_fd)
        end
      end
      dap.listeners.after.event_output[handler_id] = nil
      dap.listeners.after.event_exited[handler_id] = nil
    end,
  })

  return {
    is_complete = function()
      return is_finished
    end,
    output_stream = function()
      local index = 0
      return function()
        index = index + 1
        return output_data[index]
      end
    end,
    output = function()
      return output_path
    end,
    attach = function()
      dap.repl.open()
    end,
    stop = function()
      dap.terminate()
      if not is_finished then
        result_code = -1
        is_finished = true
        if output_fd then
          vim.uv.fs_close(output_fd)
        end
      end
    end,
    result = function()
      while not is_finished do
        vim.wait(100)
      end
      return result_code or -1
    end,
  }
end

return M
