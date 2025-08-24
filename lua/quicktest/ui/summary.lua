local Popup = require("nui.popup")
local Split = require("nui.split")
local storage = require("quicktest.storage")

local M = {}

-- Configuration
M.config = {
  join_to_panel = false,
  enabled = true
}

local api = vim.api
local storage_subscription = nil
local current_window = nil
local current_buffer = nil
local test_list = {}

-- Forward declaration
local update_display

-- Icons for test status
local icons = {
  running = "",
  passed = "✓",
  failed = "✗",
  skipped = "⊝",
  pending = "○"
}

-- Helper functions
local function find_win_by_bufnr(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end

  return -1
end

local function is_buf_visible(bufnr)
  return find_win_by_bufnr(bufnr) ~= -1
end

-- Get or create summary buffer
local function get_or_create_buf()
  -- Find existing summary buffer by filetype
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) then
      local filetype = vim.bo[buf].filetype
      if filetype == "quicktest-summary" then
        return buf
      end
    end
  end

  -- Create new buffer as scratch buffer (not listed, no file)
  local buf = api.nvim_create_buf(false, true)

  -- Set buffer options to make it a proper scratch/temporary buffer
  vim.bo[buf].filetype = "quicktest-summary"
  vim.bo[buf].buftype = "nowrite" -- Changed to nowrite instead of nofile
  vim.bo[buf].bufhidden = "wipe"  -- Changed to wipe to clean up completely
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = false -- Start as not readonly to avoid warnings
  vim.bo[buf].modified = false

  -- Don't set a name to avoid file association issues
  -- api.nvim_buf_set_name(buf, name)

  -- Add autocmd to prevent any modifications
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufModifiedSet", "BufWritePre", "BufWriteCmd" }, {
    buffer = buf,
    callback = function(ev)
      -- Always mark as unmodified and prevent writes
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modified = false
        -- Only set readonly for user-initiated changes, not our updates
        if ev.event ~= "BufModifiedSet" then
          vim.bo[buf].readonly = false -- Allow our updates to work
        end
      end

      if ev.event == "BufWritePre" or ev.event == "BufWriteCmd" then
        return true -- Cancel write operations
      end
    end,
  })

  return buf
end

-- Shared method to discover test location
local function discover_test_location(test)
  if not test or not test.name then
    return nil
  end

  if test.location and test.location ~= "" then
    return test.location
  end

  -- Try to find location from the "Running test:" entry
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

  -- If still no location, try to find parent test in test_list
  if string.match(test.name, "/") then
    local parent_name = string.match(test.name, "^([^/]+)")

    for _, parent_test in ipairs(test_list) do
      if parent_test.name == parent_name and parent_test.location and parent_test.location ~= "" then
        return parent_test.location
      end
    end
  end

  return nil
end

-- Shared method to find target window
local function find_target_window()
  if M.config.join_to_panel then
    -- Find the main editor window (not summary, not panel)
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

    -- If no suitable window found, use top window
    vim.cmd("wincmd k")
    return vim.api.nvim_get_current_win()
  else
    -- For non-joined mode, close summary and use current window
    M.close()
    return vim.api.nvim_get_current_win()
  end
end

-- Shared method to navigate to test location with function discovery
local function navigate_to_test(test, target_win, callback)
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

      -- Execute callback if provided
      if callback then
        callback()
      end
    end)
    return true
  end

  return false
end

-- Setup keybindings for summary buffer
local function setup_keybindings(buf)
  local opts = { buffer = buf, noremap = true, silent = true }

  -- Enter - jump to test location
  vim.keymap.set('n', '<CR>', function()
    local line = api.nvim_win_get_cursor(0)[1]
    local test_index = line - 3 -- Skip header lines (Total, blank, "Tests:")
    local test = test_list[test_index]

    if test then
      M.jump_to_test(test)
    end
  end, opts)

  -- r - run test
  vim.keymap.set('n', 'r', function()
    local line = api.nvim_win_get_cursor(0)[1]
    local test_index = line - 3 -- Skip header lines
    local test = test_list[test_index]

    if test then
      M.run_test(test)
    end
  end, opts)

  -- d - debug test
  vim.keymap.set('n', 'd', function()
    local line = api.nvim_win_get_cursor(0)[1]
    local test_index = line - 3 -- Skip header lines
    local test = test_list[test_index]

    if test then
      M.debug_test(test)
    end
  end, opts)
end

-- Jump to test location
function M.jump_to_test(test)
  local target_win = find_target_window()

  if navigate_to_test(test, target_win) then
    -- Focus the target window to make navigation more obvious
    vim.api.nvim_set_current_win(target_win)
  end
end

-- Run specific test
function M.run_test(test)
  local target_win = find_target_window()

  navigate_to_test(test, target_win, function()
    -- Run the test at current line
    local quicktest = require("quicktest")
    quicktest.run_line()
  end)
end

-- Debug specific test
function M.debug_test(test)
  local target_win = find_target_window()

  navigate_to_test(test, target_win, function()
    -- Debug the test at current line
    local quicktest = require("quicktest")
    quicktest.run_line("auto", "auto", { strategy = "dap" })
  end)
end

-- Create standalone summary window (right side)
local function create_standalone_window()
  local buf = get_or_create_buf()

  local popup = Popup({
    enter = false,
    bufnr = buf,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Test Summary ",
        top_align = "center"
      }
    },
    position = {
      row = "10%",
      col = "70%"
    },
    size = {
      width = "55%",
      height = "80%"
    }
  })

  popup:mount()
  setup_keybindings(buf)

  current_window = popup.winid
  current_buffer = buf

  return popup
end

-- Create joined split within panel window
function M.create_joined_split(panel_winid)
  if current_window and api.nvim_win_is_valid(current_window) then
    return -- Already created
  end

  if not panel_winid or not api.nvim_win_is_valid(panel_winid) then
    return -- Invalid panel window
  end

  local buf = get_or_create_buf()

  -- Create the desired layout: [go_file] on top, [summary | panel] on bottom
  -- First, go to the panel window and create a vertical split within it
  vim.api.nvim_set_current_win(panel_winid)
  vim.cmd("vertical 60 split")

  local new_winid = api.nvim_get_current_win()

  if not new_winid or not api.nvim_win_is_valid(new_winid) then
    return -- Failed to create split
  end

  -- Set our buffer in the new window
  api.nvim_win_set_buf(new_winid, buf)
  setup_keybindings(buf)

  -- Configure window properties
  if api.nvim_win_is_valid(new_winid) then
    vim.w[new_winid].quicktest_summary = true
    -- Don't set previewwindow for joined splits to avoid conflicts
  end

  current_window = new_winid
  current_buffer = buf

  -- Call update_display directly instead of scheduling
  update_display()
end

-- Update summary display
update_display = function()
  if not current_buffer or not api.nvim_buf_is_valid(current_buffer) then
    return
  end

  -- Verify this is actually a summary buffer
  local filetype = vim.bo[current_buffer].filetype
  if filetype ~= "quicktest-summary" then
    return
  end

  local results = storage.get_current_results()
  local summary = storage.get_run_summary()

  -- Filter test_list to only include actual tests (not status lines)
  test_list = {}
  for _, test in ipairs(results) do
    -- Skip status lines that start with "Running test:" or similar command output
    -- Also skip Go test framework output lines
    local name = test.name or ""
    if not string.match(name, "^Running test:") and
        not string.match(name, "^✓ Running test:") and
        not string.match(name, "^=== RUN") and
        not string.match(name, "^--- PASS:") and
        not string.match(name, "^--- FAIL:") and
        not string.match(name, "^PASS$") and
        not string.match(name, "^FAIL$") and
        not string.match(name, "^ok%s+") and
        name ~= "" then
      table.insert(test_list, test)
    end
  end

  -- Build header with correct filtered counts
  local filtered_summary = {
    total = 0,
    passed = 0,
    failed = 0,
    running = 0,
    skipped = 0
  }

  for _, test in ipairs(test_list) do
    filtered_summary.total = filtered_summary.total + 1
    filtered_summary[test.status] = filtered_summary[test.status] + 1
  end

  local lines = {
    string.format("Total: %d | Passed: %d | Failed: %d | Skipped: %d",
      filtered_summary.total, filtered_summary.passed, filtered_summary.failed, filtered_summary.skipped),
    "",
    "Tests:"
  }

  -- Add test entries (using filtered test_list)
  for _, test in ipairs(test_list) do
    local icon = icons[test.status] or icons.pending
    local duration_str = ""
    if test.duration then
      duration_str = string.format(" (%.2fs)", test.duration / 1000)
    end

    local line = string.format("%s %s%s", icon, test.name, duration_str)
    table.insert(lines, line)
  end

  -- Update buffer content safely
  local success = pcall(function()
    vim.bo[current_buffer].readonly = false
    vim.bo[current_buffer].modifiable = true
    api.nvim_buf_set_lines(current_buffer, 0, -1, false, lines)
    vim.bo[current_buffer].modifiable = false
    vim.bo[current_buffer].readonly = true
    vim.bo[current_buffer].modified = false
  end)

  if not success then
    return
  end

  -- Apply highlights
  if #test_list > 0 then
    for i, test in ipairs(test_list) do
      local line_idx = i + 2 -- Skip header lines
      local hl_group = "Normal"

      if test.status == "passed" then
        hl_group = "DiagnosticOk"
      elseif test.status == "failed" then
        hl_group = "DiagnosticError"
      elseif test.status == "running" then
        hl_group = "DiagnosticWarn"
      elseif test.status == "skipped" then
        hl_group = "DiagnosticHint"
      end

      pcall(api.nvim_buf_add_highlight, current_buffer, -1, hl_group, line_idx, 0, -1)
    end
  end
end

-- Public API
function M.is_open()
  return current_buffer and api.nvim_buf_is_valid(current_buffer) and is_buf_visible(current_buffer)
end

function M.open()
  if M.is_open() then
    return
  end

  if M.config.join_to_panel then
    local panel = require("quicktest.ui.panel")
    if panel.is_split_opened() then
      -- If panel is already open, create/join the summary split directly
      local panel_winid = panel.get_split_winid()
      if panel_winid ~= -1 then
        M.create_joined_split(panel_winid)
      end
    else
      -- If panel is not open, open it. create_joined_split will be called via the panel's autocmd.
      panel.try_open_win("split")
    end
  else
    create_standalone_window()
    update_display()
  end
end

function M.close()
  if current_window and api.nvim_win_is_valid(current_window) then
    pcall(api.nvim_win_close, current_window, true)
  end
  current_window = nil
  -- Don't set current_buffer to nil, keep reference for reuse
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

-- Initialize summary and subscribe to storage events
function M.init()
  if storage_subscription then
    return -- Already initialized
  end

  storage_subscription = function(event_type, data)
    if event_type == 'run_started' then
      test_list = {}
      if M.is_open() then
        update_display()
      end
    elseif event_type == 'test_started' then
      if M.is_open() then
        update_display()
      end
    elseif event_type == 'test_finished' then
      if M.is_open() then
        update_display()
      end
      -- Ignore test_output events to avoid showing status lines in summary
    end
  end

  storage.subscribe(storage_subscription)
end

-- Clean up summary subscription
function M.cleanup()
  if storage_subscription then
    storage.unsubscribe(storage_subscription)
    storage_subscription = nil
  end
  M.close()
  current_buffer = nil
  test_list = {}
end

return M

