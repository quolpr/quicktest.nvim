local Job = require("plenary.job")

local M = {
  name = "vitest",
}
---@class VitestRunParams
---@field func_names string[]
---@field bufnr integer
---@field cursor_pos integer[]

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@return VitestRunParams
M.build_line_run_params = function(bufnr, cursor_pos)
  print("bufnr", bufnr)
  -- You can get current function name to run based on bufnr and cursor_pos
  -- Check hot it is done for golang at `lua/quicktest/adapters/golang`
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    func_names = {},
    -- Add other parameters as needed
  }
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return VitestRunParams
M.build_file_run_params = function(bufnr, cursor_pos)
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    -- Add other parameters as needed
  }
end

--- Determines if the test can be run with the given parameters.
---@param params VitestRunParams
---@return boolean, string
M.can_run = function(params)
  if not params.func_names or #params.func_names == 0 then
    return false, "No tests to run"
  end

  -- Implement logic to determine if the test can be run
  return true, ""
end

--- Executes the test with the given parameters.
---@param params VitestRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local job = Job:new({
    command = "test_command",
    args = { "--some-flag" }, -- Modify based on how your test command needs to be structured
    on_stdout = function(_, data)
      send({ type = "stdout", output = data })
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()

  return job.pid
end

---@param params VitestRunParams
M.title = function(params)
  return "Running test: " .. vim.inspect(params)
end

--- Handles actions to take after the test run, based on the results.
---@param params any
---@param results any
M.after_run = function(params, results)
  -- Implement actions based on the results, such as updating UI or handling errors
end

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return vim.endswith(bufname, "test.ts") or vim.endswith(bufname, "test.js")
end

return M
