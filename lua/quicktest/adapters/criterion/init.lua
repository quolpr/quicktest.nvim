local Job = require("plenary.job")

local util = require("quicktest.adapters.criterion.util")
local meson = require("quicktest.adapters.criterion.meson")
local criterion = require("quicktest.adapters.criterion.criterion")

local ns = vim.api.nvim_create_namespace("quicktest-criterion")

---@class CriterionAdapterOptions
---@field builddir (fun(buf: integer): string)?
local M = {
  name = "criterion",
  test_results = {},
  ---@type CriterionAdapterOptions
  options = {},
}

---@class Test
---@field test_suite string
---@field test_name string

---@class CriterionTestParams
---@field test Test
---@field test_exe string
---@field bufnr integer
---@field cursor_pos integer[]

---@param bufnr integer
---@param cursor_pos integer[]
---@return CriterionTestParams | nil,  string | nil
M.build_file_run_params = function(bufnr, cursor_pos)
  local builddir = M.options.builddir and M.options.builddir(bufnr) or "build"
  local test_exe = util.get_test_exe_from_buffer(bufnr, builddir)

  if test_exe == "" then
    return nil, "No test executable was found in " .. builddir
  end

  return {
    test = {},
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return CriterionTestParams | nil,  string | nil
M.build_line_run_params = function(bufnr, cursor_pos)
  local line = criterion.get_nearest_test(bufnr, cursor_pos)

  if line == "" then
    return nil, "No test to run"
  end

  local builddir = M.options.builddir and M.options.builddir(bufnr) or "build"
  local test_exe = util.get_test_exe_from_buffer(bufnr, builddir)

  if test_exe == "" then
    return nil, "No test executable was found in " .. builddir
  end

  local test = criterion.get_test_suite_and_name(line)
  return {
    test = test,
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }, nil
end

--- Executes the test with the given parameters.
---@param params CriterionTestParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  -- Build the project so we can show potential build errors in the UI.
  -- Otherwise the test will fail silently-ish providing little insight to the user.

  local builddir = M.options.builddir and M.options.builddir(params.bufnr) or "build"
  local compile = meson.compile(builddir)

  if compile.return_val ~= 0 then
    for _, line in ipairs(compile.text) do
      send({ type = "stderr", output = line })
    end
    send({ type = "exit", code = compile.return_val })
    return -1
  end

  local test_output = ""

  --- Run the tests
  local job = Job:new({
    command = params.test_exe,
    args = criterion.make_test_args(params.test.test_suite, params.test.test_name),
    on_stdout = function(_, data)
      test_output = test_output .. data
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      M.test_results = vim.json.decode(test_output)
      util.print_results(M.test_results, send)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()
  return job.pid -- Return the process ID
end

--- Handles actions to take after the test run, based on the results.
---@param params CriterionTestParams
---@param results any
M.after_run = function(params, results)
  local diagnostics = {}
  for _, error in ipairs(util.get_error_messages(M.test_results)) do
    local line_no = criterion.locate_error(error)
    if line_no then
      table.insert(diagnostics, {
        lnum = line_no - 1, -- lnum seems to be 0-based
        col = 0,
        severity = vim.diagnostic.severity.ERROR,
        message = "FAILED",
        source = "Test",
        user_data = "test",
      })
    end
  end

  vim.diagnostic.set(ns, params.bufnr, diagnostics, {})
end

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = util.get_filename(bufname)
  return vim.startswith(filename, "test_") and vim.endswith(filename, ".c")
end

---@param params CriterionTestParams
---@return string
M.title = function(params)
  if params.test.test_suite ~= nil and params.test.test_name ~= nil then
    return "Testing " .. params.test.test_suite .. "/" .. params.test.test_name
  else
    return "Running tests from " .. params.test_exe
  end
end

--- Adapter options
setmetatable(M, {
  ---@param opts CriterionAdapterOptions
  __call = function(_, opts)
    M.options = opts
    return M
  end,
})

return M
