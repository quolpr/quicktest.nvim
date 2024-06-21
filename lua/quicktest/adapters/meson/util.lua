local Job = require("plenary.job")
local json5 = require("json5")
local meson = require("quicktest.adapters.meson.meson")

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
    send({ type = "stdout", output = ts["name"] })
    for _, test in ipairs(ts["tests"]) do
      -- print(vim.inspect(test))
      if test["status"] ~= "SKIPPED" then
        send({ type = "stdout", output = "  " .. test["name"] .. ": " .. test["status"] })
        if test["messages"] then
          for _, msg in ipairs(test["messages"]) do
            send({ type = "stdout", output = "    " .. msg })
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

-- Uses meson introspect CLI to find the name of the test
-- executable from the path of the open file
function M.get_test_exe_from_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local targets = meson.get_targets()
  for _, target in ipairs(targets) do
    -- print(vim.inspect(target["target_sources"]))
    for _, target_source in ipairs(target["target_sources"]) do
      -- print(vim.inspect(source))
      for _, source in ipairs(target_source["sources"]) do
        -- print(vim.inspect(source))
        if source == bufname then
          return target["name"]
        end
      end
    end
  end
  return nil
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

  table.insert(test_args, "-v")

  local ts = params.test.test_suite or "*"
  local tn = params.test.test_name or "*"

  local ta = "--filter=" .. ts .. "/" .. tn .. " --json"
  table.insert(test_args, "--test-args=" .. ta)
  return test_args
end

return M
