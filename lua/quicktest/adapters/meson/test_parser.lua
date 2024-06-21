local M = {}

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

function M.get_test_suite_and_name(line)
  local parts = splitstr(line, "(")
  local index = 1

  if vim.startswith(parts[1], "ParameterizedTest") then
    index = 2
  end

  parts = splitstr(parts[2], ",")
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

return M
