local Job = require("plenary.job")
local json5 = require("json5")

local M = {}

function M.capture_json(data, json)
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

function M.print_results(data, params, send)
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

function M.get_filename(path)
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
function M.get_test_exe_from_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = M.get_filename(bufname)
  filename = string.gsub(filename, ".c", "", 1)
  return filename
end

function M.get_test_suite_and_name(line)
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

function M.get_nearest_test(bufnr, cursor_pos)
  for pos = cursor_pos[1], 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, pos - 1, pos, true)[1]
    if vim.startswith(line, "Test(") or vim.startswith(line, "ParameterizedTest(") then
      return line
    end
  end
end

function M.build_tests(send)
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
  return build_ok
end

function M.make_test_args(params)
  local test_args = { "test", "-C", "build" }

  if params.test_exe then
    table.insert(test_args, params.test_exe)
  end

  local ts = params.test.test_suite or "*"
  local tn = params.test.test_name or "*"
  table.insert(test_args, "--test-args=--filter=" .. ts .. "/" .. tn)

  table.insert(test_args, "--test-args=--json")
  table.insert(test_args, "-v")

  --print(vim.inspect(test_args))
  return test_args
end

return M
