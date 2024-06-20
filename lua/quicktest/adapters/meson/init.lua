local Job = require("plenary.job")
local util = require("quicktest.adapters.meson.util")

local M = {
  name = "meson test runner for C assuming Criterion test frame work",
}

local parsed_test_output = {}

M.build_file_run_params = function(bufnr, cursor_pos)
  local test_exe = util.get_test_exe_from_buffer(bufnr)
  return {
    test = {},
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }
end

M.build_line_run_params = function(bufnr, cursor_pos)
  local test_exe = util.get_test_exe_from_buffer(bufnr)
  local line = util.get_nearest_test(bufnr, cursor_pos)
  local test = util.get_test_suite_and_name(line)
  return {
    test = test,
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }
end
--- Determines if the test can be run with the given parameters.
---@param params any
---@return boolean
M.can_run = function(params)
  -- Implement logic to determine if the test can be run
  return true
end

--- Executes the test with the given parameters.
---@param params any
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  if util.build_tests(send) == false then
    return -1
  end

  local job = Job:new({
    command = "meson",
    args = util.make_test_args(params),
    on_stdout = function(_, data)
      data = util.capture_json(data, parsed_test_output)
      if data then
        util.print_results(parsed_test_output.text, params, send)
      end
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()
  return job.pid -- Return the process ID
end

--- Handles actions to take after the test run, based on the results.
---@param params any
---@param results any
M.after_run = function(params, results)
  -- Implement actions based on the results, such as updating UI or handling errors
  -- print(vim.inspect(params.data))
  if parsed_test_output.text == nil then
    return
  end
  -- print(xml_output.text)
  -- print(vim.inspect(parsed_data))
  -- print(parsed_data["id"])
  -- print(parsed_data["test_suites"][1]["name"])
end

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = util.get_filename(bufname)
  return vim.startswith(filename, "test_") and vim.endswith(filename, ".c")
end

M.title = function(params)
  if params.test.test_suite ~= nil and params.test.test_name ~= nil then
    return "Testing " .. params.test.test_suite .. "/" .. params.test.test_name
  else
    return "Running tests from " .. params.test_exe
  end
end

return M
