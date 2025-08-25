local storage = require("quicktest.storage")
local ts = require("quicktest.ts")

---@class StatusConfig
---@field enabled boolean
---@field signs boolean

---@param opts StatusConfig?
---@return table
return function(opts)
  opts = opts or {}
  
  local M = {}
  M.name = "status"
  
  -- Configuration with defaults
  M.config = vim.tbl_deep_extend("force", {
    enabled = true,
    signs = true
  }, opts)

local api = vim.api
local storage_subscription = nil
local sign_group = "quicktest-status"

-- Status definitions
local statuses = {
  passed = { text = "✓", texthl = "DiagnosticOk" },
  failed = { text = "✗", texthl = "DiagnosticError" },
  skipped = { text = "⊝", texthl = "DiagnosticHint" },
  running = { text = "", texthl = "DiagnosticWarn" },
}

-- Initialize signs
local function init_signs()
  -- Define signs for each status
  for status, conf in pairs(statuses) do
    vim.fn.sign_define("quicktest_" .. status, {
      text = conf.text,
      texthl = conf.texthl
    })
  end
end

-- Get test function locations in buffer using treesitter
local function get_test_locations(bufnr)
  local locations = {}
  
  -- Try to get Go test functions using treesitter
  local success, go_ts = pcall(require, "quicktest.adapters.golang.ts")
  
  if success and go_ts then
    -- Get all function names first
    local func_names = go_ts.get_func_names(bufnr)
    
    -- Get line numbers for each test function
    for _, func_name in ipairs(func_names) do
      if func_name:match("^Test") then  -- Only test functions
        local line_no = go_ts.get_func_def_line_no(bufnr, func_name)
        if line_no then
          locations[func_name] = line_no
        end
      end
    end
  else
    -- Fallback: search for test functions manually
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      local func_name = line:match("^func%s+(Test%w+)")
      if func_name then
        locations[func_name] = i - 1  -- Convert to 0-based
      end
    end
  end
  
  return locations
end

-- Place sign at specific line in buffer
local function place_sign(bufnr, line_no, status)
  if not M.config.signs or not api.nvim_buf_is_valid(bufnr) or vim.fn.buflisted(bufnr) == 0 then
    return
  end
  
  local line_count = api.nvim_buf_line_count(bufnr)
  local line_number = line_no + 1  -- Convert to 1-based for sign_place
  
  if line_number <= line_count then
    vim.fn.sign_place(0, sign_group, "quicktest_" .. status, bufnr, {
      lnum = line_number,
      priority = 1000,
    })
  end
end


-- Clear all signs from buffer
local function clear_buffer_status(bufnr)
  if api.nvim_buf_is_valid(bufnr) then
    vim.fn.sign_unplace(sign_group, { buffer = bufnr })
  end
end

-- Update status display for a specific buffer
local function update_buffer_status(bufnr)
  if not api.nvim_buf_is_valid(bufnr) or vim.fn.buflisted(bufnr) == 0 then
    return
  end
  
  -- Clear existing status
  clear_buffer_status(bufnr)
  
  -- Get test results
  local results = storage.get_current_results()
  if not results or #results == 0 then
    return
  end
  
  -- Get test function locations in this buffer
  local test_locations = get_test_locations(bufnr)
  
  -- Place status for each test result
  for _, result in ipairs(results) do
    if result.name and result.status then
      local line_no = test_locations[result.name]
      if line_no then
        -- Place sign
        if M.config.signs then
          place_sign(bufnr, line_no, result.status)
        end
      end
    end
  end
end

-- Update status display for all relevant buffers
local function update_all_buffers()
  -- Find all test buffers (both with and without results)
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) and vim.fn.buflisted(bufnr) ~= 0 then
      local buf_name = api.nvim_buf_get_name(bufnr)
      -- Only update Go test files for now
      if buf_name:match("_test%.go$") then
        update_buffer_status(bufnr)
      end
    end
  end
end

-- Update status display for all currently visible test buffers
local function update_visible_test_buffers()
  -- Get all visible windows and their buffers
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(win) then
      local bufnr = api.nvim_win_get_buf(win)
      if api.nvim_buf_is_valid(bufnr) and vim.fn.buflisted(bufnr) ~= 0 then
        local buf_name = api.nvim_buf_get_name(bufnr)
        if buf_name:match("_test%.go$") then
          update_buffer_status(bufnr)
        end
      end
    end
  end
end

-- Initialize status consumer and subscribe to storage events
function M.init()
  if storage_subscription then
    return -- Already initialized
  end
  
  -- Initialize signs
  init_signs()
  
  storage_subscription = function(event_type, data)
    if event_type == 'run_started' then
      -- Clear all status when new run starts
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        clear_buffer_status(bufnr)
      end
    elseif event_type == 'test_started' then
      -- Update status when test starts (show running) - prioritize visible buffers
      -- The data contains the test with status = 'running'
      update_visible_test_buffers()
    elseif event_type == 'test_finished' then
      -- Update status when test finishes - prioritize visible buffers
      -- The data contains the test with final status (passed/failed/skipped)
      update_visible_test_buffers()
    end
  end
  
  storage.subscribe(storage_subscription)
  
  -- Set up autocmds for buffer events
  local group = api.nvim_create_augroup("quicktest-status", { clear = true })
  
  -- Update status when entering a test buffer
  api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*_test.go",
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      update_buffer_status(bufnr)
    end,
  })
  
  -- Update status when a new test buffer is opened/read
  api.nvim_create_autocmd({"BufReadPost", "BufNewFile"}, {
    group = group,
    pattern = "*_test.go",
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      -- Use vim.schedule to ensure buffer is fully loaded
      vim.schedule(function()
        if api.nvim_buf_is_valid(bufnr) then
          update_buffer_status(bufnr)
        end
      end)
    end,
  })
  
  -- Update all visible test buffers when window layout changes
  api.nvim_create_autocmd({"WinEnter", "WinNew"}, {
    group = group,
    callback = function()
      -- Use vim.schedule to avoid issues during window creation
      vim.schedule(function()
        update_visible_test_buffers()
      end)
    end,
  })
  
  -- Clear status when buffer is deleted
  api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      clear_buffer_status(bufnr)
    end,
  })
  
  -- Initial update of all currently visible test buffers
  vim.schedule(function()
    update_visible_test_buffers()
  end)
end

-- Clean up status subscription
function M.cleanup()
  if storage_subscription then
    storage.unsubscribe(storage_subscription)
    storage_subscription = nil
  end
  
  -- Clear all status from all buffers
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    clear_buffer_status(bufnr)
  end
  
  -- Clear autocmds
  local ok, group_id = pcall(api.nvim_get_autocmds, { group = "quicktest-status" })
  if ok and #group_id > 0 then
    api.nvim_clear_autocmds({ group = "quicktest-status" })
  end
end

-- Public API for manual status updates
function M.update()
  update_all_buffers()
end

-- Clear all status
function M.clear()
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    clear_buffer_status(bufnr)
  end
end

  return M
end
