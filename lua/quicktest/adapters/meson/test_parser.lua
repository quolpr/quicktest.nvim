local M = {}
---Split string on the given separator
---Copied from https://www.tutorialspoint.com/how-to-split-a-string-in-lua-programming
---@param inputstr string
---@param sep string
---@return string[]
local function splitstr(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

---Parse a test declaration to get the name of the suite and test
---This function assumes the Criterion unit test framework
---Expected input is one of
--- ParameterizedTest(struct param_type* param, test_suite, test_name...)
--- Test(test_suite, test_name, ...)
---Returns the test suite and name in a table
---@param line string
---@return table
function M.get_test_suite_and_name(line)
  local parts = splitstr(line, "(")
  local index = 1

  if vim.startswith(parts[1], "ParameterizedTest") then
    index = 2 -- Skip over param
  end

  parts = splitstr(parts[2], ",")
  return {
    test_suite = string.gsub(parts[index], "%s+", ""), -- Trim whitespace
    test_name = string.gsub(parts[index + 1], "%s+", ""),
  }
end

---Try to find the test definition closest to the cursor position.
---This function assumes the Criterion unit test framework.
---In this context 'nearest' is the first definition found when searching toward the start of the file.
---If the cursor is on or within a function then this function's name is returned, otherwise search "up"
---for next possible match.
---@param bufnr integer
---@param cursor_pos integer[]
---@return string | nil
function M.get_nearest_test(bufnr, cursor_pos)
  for pos = cursor_pos[1], 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, pos - 1, pos, true)[1]
    if vim.startswith(line, "Test(") or vim.startswith(line, "ParameterizedTest(") then
      return line
    end
  end
end

return M
