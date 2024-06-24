local meson = require("quicktest.adapters.criterion.meson")

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

---Get all error messages
---@param result_json table
---@return table
function M.get_error_messages(result_json)
  local errors = {}

  for _, ts in ipairs(result_json["test_suites"]) do
    for _, test in ipairs(ts["tests"]) do
      if test["status"] == "FAILED" and test["messages"] then
        for _, msg in ipairs(test["messages"]) do
          table.insert(errors, msg)
        end
      end
    end
  end
  return errors
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
---@return string
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
          return target["filename"][1]
        end
      end
    end
  end
  return ""
end

return M
