local Job = require("plenary.job")

local M = {
  name = "meson test runner for C assuming Criterion test frame work",
}

local function get_filename(path)
  return path:match("[^/]*.c$")
end

-- Assumes the test executable is named the same as the test except for the file ending
-- e.g. test_name.c -> test_name
local function get_test_exe_from_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = get_filename(bufname)
  filename = string.gsub(filename, ".c", "", 1)
  return filename
end

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@return any
M.build_params = function(bufnr, cursor_pos)
  -- You can get current function name to run based on bufnr and cursor_pos
  -- Check hot it is done for golang at `lua/quicktest/adapters/golang`
  print("HERPA DERPA")
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    -- Add other parameters as needed
  }
end

M.build_file_run_params = function(bufnr, cursor_pos)
  local test_exe = get_test_exe_from_buffer(bufnr)
  return {
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }
end

M.build_line_run_params = function(bufnr, cursor_pos)
  local test_exe = get_test_exe_from_buffer(bufnr)
  return {
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
  local test_args = { "test", "-C", "build" }

  if params.test_exe then
    table.insert(test_args, params.test_exe)
  end

  local job = Job:new({
    command = "meson",
    args = test_args, -- Modify based on how your test command needs to be structured
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
  return job.pid -- Return the process ID
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
  local filename = get_filename(bufname)
  return vim.startswith(filename, "test_") and vim.endswith(filename, ".c")
end

M.title = function(params)
  return "HERPA DERP TITLE"
end

return M