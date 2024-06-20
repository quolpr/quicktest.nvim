local Job = require("plenary.job")
local json5 = require("json5")

local M = {
  name = "meson test runner for C assuming Criterion test frame work",
}

local parsed_test_output = {}

local function capture_json(data, json)
  local complete = false

  if vim.startswith(data, "{") then
    json.open = true
    json.text = ""
  end

  if json.open then
    json.text = json.text .. data .. "\n"
  end

  if vim.startswith(data, "}") then
    json.open = false
    complete = true
  end

  return complete
end

local function print_results(data, params, send)
  local parsed = json5.parse(data)
  -- print(vim.inspect(parsed))
  for _, ts in ipairs(parsed["test_suites"]) do
    -- print(vim.inspect(ts))
    if params.test.test_suite == nil or params.test.test_suite == ts["name"] then
      for _, test in ipairs(ts["tests"]) do
        -- print(vim.inspect(test))
        if params.test.test_name == nil or params.test.test_name == test["name"] then
          send({ type = "stdout", output = test["name"] .. ": " .. test["status"] })
          if test["messages"] then
            for _, msg in ipairs(test["messages"]) do
              send({ type = "stdout", output = "  " .. msg })
            end
          end
        end
      end
    end
  end
end

local function capture_xml(data, xml)
  local returned_data = data

  if vim.startswith(data, "<?xml") then
    xml.open = true
    xml.text = ""
  end

  if xml.open then
    xml.text = xml.text .. data .. "\n"
    returned_data = nil
  end

  if vim.startswith(data, "</testsuites>") then
    xml.open = false
  end

  return returned_data
end

local function get_filename(path)
  return path:match("[^/]*.c$")
end

local function mysplit(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

-- Assumes the test executable is named the same as the test except for the file ending
-- e.g. test_name.c -> test_name
local function get_test_exe_from_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = get_filename(bufname)
  filename = string.gsub(filename, ".c", "", 1)
  return filename
end

local function get_test_suite_and_name(line)
  local parts = mysplit(line, "(")
  local index = 1

  if vim.startswith(parts[1], "ParameterizedTest") then
    index = 2
  end

  parts = mysplit(parts[2], ",")
  return {
    test_suite = string.gsub(parts[index], "%s+", ""),
    test_name = string.gsub(parts[index + 1], "%s+", ""),
  }
end

local function get_nearest_test(bufnr, cursor_pos)
  for pos = cursor_pos[1], 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, pos - 1, pos, true)[1]
    if vim.startswith(line, "Test(") or vim.startswith(line, "ParameterizedTest(") then
      return line
    end
  end
end

M.build_file_run_params = function(bufnr, cursor_pos)
  local test_exe = get_test_exe_from_buffer(bufnr)
  return {
    test = {},
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }
end

M.build_line_run_params = function(bufnr, cursor_pos)
  local test_exe = get_test_exe_from_buffer(bufnr)
  local line = get_nearest_test(bufnr, cursor_pos)
  local test = get_test_suite_and_name(line)
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
  local test_args = { "test", "-C", "build" }

  if params.test_exe then
    table.insert(test_args, params.test_exe)
  end

  local ts = params.test.test_suite or "*"
  local tn = params.test.test_name or "*"
  table.insert(test_args, "--test-args=--filter=" .. ts .. "/" .. tn)

  table.insert(test_args, "--test-args=--json")
  table.insert(test_args, "-v")

  print(vim.inspect(test_args))

  local build_ok = false
  local build_out = {}
  local build = Job:new({
    command = "meson",
    args = { "compile", "-C", "build" },
    on_stdout = function(_, data)
      table.insert(build_out, data)
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      build_ok = return_val == 0
      if build_ok == false then
        for _, value in ipairs(build_out) do
          send({ type = "stdout", output = value })
        end
        send({ type = "exit", code = return_val })
      end
    end,
  })
  build:start()
  Job.join(build)

  if build_ok == false then
    return -1
  end

  local job = Job:new({
    command = "meson",
    args = test_args, -- Modify based on how your test command needs to be structured
    on_stdout = function(_, data)
      data = capture_json(data, parsed_test_output)
      if data then
        print_results(parsed_test_output.text, params, send)
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
  local parsed_data = json5.parse(parsed_test_output.text)
  -- print(vim.inspect(parsed_data))
  -- print(parsed_data["id"])
  -- print(parsed_data["test_suites"][1]["name"])
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
  if params.test.test_suite ~= nil and params.test.test_name ~= nil then
    return "Testing " .. params.test.test_suite .. "/" .. params.test.test_name
  else
    return "Running tests from " .. params.test_exe
  end
end

return M
