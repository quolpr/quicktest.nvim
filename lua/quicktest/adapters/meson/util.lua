local json5 = require("json5")
local meson = require("quicktest.adapters.meson.meson")

local M = {}

---Split string on the given separator
---Copied from https://www.tutorialspoint.com/how-to-split-a-string-in-lua-programming
---@param inputstr string
---@param sep string
---@return string[]
function M.splitstr(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

---@class JsonContext
---@field open boolean State indicating opening bracket has been found and data should be added to the text field
---@field text string All JSON text

---This function is fed all output from running the test executable and tries to capture a JSON-document in the stream.
---It searches for the opening and closing brackets both of which are assumed to be on new lines.
---This function assumes the pretty-printed JSON data as output from the criterion test exectuable when passed the '--json' argument
---Return true if JSON was successfully captured.
---@param data string
---@param json JsonContext
---@return table | nil
function M.capture_json(data, json)
  local result = nil

  if vim.startswith(data, "{") then
    json.open = true
    json.text = ""
  end

  if json.open then
    json.text = json.text .. data .. "\n"
  end

  if vim.startswith(data, "}") then
    json.open = false
    result = json5.parse(json.text)
  end

  return result
end

---Prints the test results using the callback provided by the plugin
---@param result_json table
---@param send fun(data: any)
function M.print_results(result_json, send)
  -- print(vim.inspect(result_json))
  for _, ts in ipairs(result_json["test_suites"]) do
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

---Get the filename of a C source file by removing the path
---@param path string path/to/file.c
---@return string
function M.get_filename(path)
  return path:match("[^/]*.c$")
end

---Uses meson introspect CLI to find the name of the test executable using the path of the file that is open in the given buffer
---Meson will output a JSON document with the name of all executables and sources used to build them, among other information.
---We want to find a test executable that uses the source file that is open in the given buffer.
---@note This function finds the first match. There is nothing preventing someone from using the same source file in multiple test exectuables,
---so that is a known limitation and is currently not handled.
---@param bufnr integer
---@param builddir string
---@return string | nil
function M.get_test_exe_from_buffer(bufnr, builddir)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local targets = meson.get_targets(builddir)
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

---Make the arguments to pass to 'meson test'
---This function assumes the test executable is built with Criterion
---@param test_exe string Name of test executable
---@param test_suite string | nil
---@param test_name string | nil
---@return table
function M.make_test_args(test_exe, test_suite, test_name)
  local test_args = { "test", "-C", "build" }

  table.insert(test_args, test_exe)

  ---Enable verbose mode so test_exe output is written to console
  table.insert(test_args, "-v")

  ---Pass arguments to the test executable
  ---We pass --json to enable test results as a JSON document
  ---We pass --filter=test_suite/test_name to run the named test under the named suite (or all if not specified)
  local ts = test_suite or "*"
  local tn = test_name or "*"
  local ta = "--filter=" .. ts .. "/" .. tn .. " --json"
  table.insert(test_args, "--test-args=" .. ta)
  return test_args
end

---Locate the line number with the error from the given error message
---Example: /some/path/to/test_module.c:42:
---@param msg string
---@return integer | nil
function M.locate_error(msg)
  local s = M.splitstr(msg, ":")
  if s[2] then
    return tonumber(s[2])
  end
end

return M
