-- Navigation utilities for jumping to test locations
local M = {}

-- Helper to find appropriate target window (avoid summary/panel windows)
local function find_target_window()
  -- Always find the main editor window (not summary, not panel)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local win_buf = vim.api.nvim_win_get_buf(win)
      local buf_name = vim.api.nvim_buf_get_name(win_buf)
      local is_panel = vim.w[win].quicktest_panel
      local is_summary = vim.w[win].quicktest_summary

      -- Skip our special windows
      if not string.match(buf_name, "quicktest://") and
          not is_panel and
          not is_summary then
        return win
      end
    end
  end

  -- If no suitable window found, create a new one
  vim.cmd("new")
  return vim.api.nvim_get_current_win()
end

-- Discover test location with function discovery
local function discover_test_location(test)
  if not test or not test.name then
    return nil
  end

  if test.location and test.location ~= "" then
    return test.location
  end

  -- Try to find location from the "Running test:" entry
  local storage = require("quicktest.storage")
  local raw_results = storage.get_current_results()
  for _, result in ipairs(raw_results) do
    if result.name and string.match(result.name, "^Running test:") and result.location and result.location ~= "" then
      local test_name_pattern = test.name
      if string.match(test.name, "/") then
        -- For sub-tests, use the parent test name
        test_name_pattern = string.match(test.name, "^([^/]+)")
      end

      if string.match(result.name, test_name_pattern) then
        return result.location
      end
    end
  end

  return nil
end

-- Navigate to test location with function discovery
---@param test TestResult
---@param callback function? Optional callback to run after navigation
---@return boolean success
function M.jump_to_test(test, callback)
  if not test then
    return false
  end

  local location = discover_test_location(test)
  if not location then
    return false
  end

  local parts = vim.split(location, ":")
  if #parts < 1 then
    return false
  end

  local file = parts[1]
  local line = tonumber(parts[2]) or 1

  local target_win = find_target_window()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_call(target_win, function()
      vim.cmd("edit " .. vim.fn.fnameescape(file))

      -- If no specific line number, try to find the test function
      if line == 1 and test and test.name then
        local test_name = test.name

        -- For Go sub-tests, use the parent test name to find the function
        if string.match(test_name, "/") then
          test_name = string.match(test_name, "^([^/]+)")
        end

        -- Search for the test function definition
        local search_pattern = "func " .. test_name .. "("
        local found_line = vim.fn.search("\\V" .. vim.fn.escape(search_pattern, "\\"), "nw")

        if found_line > 0 then
          line = found_line
        end
      end

      vim.api.nvim_win_set_cursor(target_win, { line, 0 })
    end)
    
    -- Focus the target window
    vim.api.nvim_set_current_win(target_win)
    
    -- Run callback if provided
    if callback then
      callback()
    end
    
    return true
  end

  return false
end

return M