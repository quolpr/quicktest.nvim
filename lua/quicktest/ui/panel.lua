local event = require("nui.utils.autocmd").event
local Popup = require("nui.popup")
local Split = require("nui.split")
local storage = require("quicktest.storage")
local colorized_printer = require("quicktest.colored_printer")

local M = {}

local api = vim.api
local printer = colorized_printer.new()
local storage_subscription = nil
local has_started = false  -- Track if we've already started

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

local was_buf_initialized = {}

-- Function to get or create a buffer with a specific name
local function get_or_create_buf(name)
  local full_name = "quicktest://" .. name

  local init_buf = function(buf)
    api.nvim_buf_set_name(buf, full_name)

    vim.bo[buf].undolevels = -1
    vim.bo[buf].filetype = "quicktest-output"
    vim.bo[buf].swapfile = false
    vim.bo[buf].buftype = "nofile"  -- Changed to nofile - not a real file
    vim.bo[buf].bufhidden = "hide"  -- Hide when not displayed
    vim.bo[buf].buflisted = false   -- Don't list in buffer list
    vim.bo[buf].modified = false -- Start as unmodified

    -- Add autocmd to prevent modification flag
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufModifiedSet" }, {
      buffer = buf,
      callback = function()
        if vim.bo[buf].modified then
          vim.bo[buf].modified = false
        end
      end,
    })

    was_buf_initialized[buf] = true
  end

  -- Find buffer with name if it exists
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local buf_name = api.nvim_buf_get_name(buf)
    if buf_name == full_name then
      if not was_buf_initialized[buf] then
        init_buf(buf)
      end

      return buf
    end
  end

  -- Create new buffer if not found
  local buf = api.nvim_create_buf(false, true)

  init_buf(buf)

  return buf
end

-- Get or create buffers with specific names
local function get_split_buf()
  return get_or_create_buf("quicktest-split")
end

local function get_popup_buf()
  return get_or_create_buf("quicktest-popup")
end

M.get_buffers = function()
  return { get_split_buf(), get_popup_buf() }
end
M.is_split_opened = function()
  return is_buf_visible(get_split_buf())
end
M.is_popup_opened = function()
  return is_buf_visible(get_popup_buf())
end


local function open_popup()
  local popup_options = vim.tbl_deep_extend("force", {
    enter = false,  -- Don't enter the popup window by default
    bufnr = get_popup_buf(),
    focusable = false,
    border = {
      style = "rounded",
    },
    position = "50%",
    size = {
      width = "80%",
      height = "60%",
    },
  }, require("quicktest").config.popup_options)

  local popup = Popup(popup_options)
  popup:mount()
  
  -- Configure window to be less attractive for buffer switching
  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    -- Mark window as special/utility window
    vim.w[popup.winid].quicktest_panel = true
    -- Set window as "previewwindow" - Neovim avoids these for normal buffer operations  
    vim.api.nvim_win_set_option(popup.winid, 'previewwindow', true)
  end
end

local function open_split()
  local split = Split({
    relative = "editor",
    position = "bottom",
    size = "30%",
    enter = false,
    bufnr = get_split_buf(),
  })

  split.bufnr = get_split_buf()
  split:mount()
  
  -- Configure window to be less attractive for buffer switching
  if split.winid and vim.api.nvim_win_is_valid(split.winid) then
    -- Mark window as special/utility window
    vim.w[split.winid].quicktest_panel = true
    -- Set window as "previewwindow" - Neovim avoids these for normal buffer operations
    vim.api.nvim_win_set_option(split.winid, 'previewwindow', true)
  end
end

local function try_open_split()
  if not M.is_split_opened() then
    open_split()
  end
end

local function try_open_popup()
  if not M.is_popup_opened() then
    open_popup()
  end
end

---@param mode WinModeWithoutAuto
function M.try_open_win(mode)
  if mode == "popup" then
    try_open_popup()
  else
    try_open_split()
  end
end

---@param mode WinModeWithoutAuto
function M.try_close_win(mode)
  local win_id
  if mode == "popup" then
    win_id = find_win_by_bufnr(get_popup_buf())
  else
    win_id = find_win_by_bufnr(get_split_buf())
  end

  if win_id ~= -1 then
    vim.api.nvim_win_close(win_id, true)
  end
end

---@param buf number
function M.scroll_down(buf)
  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    local win_bufnr = vim.api.nvim_win_get_buf(win)
    if win_bufnr == buf then
      local line_count = vim.api.nvim_buf_line_count(buf)

      if line_count < 3 then
        return
      end

      vim.api.nvim_win_set_cursor(win, { line_count - 2, 0 })
    end
  end
end

---@param buf number
function M.should_continue_scroll(buf)
  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    local win_bufnr = vim.api.nvim_win_get_buf(win)
    if win_bufnr == buf then
      local current_pos = vim.api.nvim_win_get_cursor(win)
      local line_count = vim.api.nvim_buf_line_count(buf)

      return current_pos[1] >= line_count - 2
    end
  end
end

-- Initialize panel and subscribe to storage events
function M.init()
  if storage_subscription then
    return -- Already initialized
  end
  
  storage_subscription = function(event_type, data)
    if event_type == 'test_output' then
      M.handle_output(data)
    elseif event_type == 'run_started' then
      -- Reset for new test run
      has_started = false
    elseif event_type == 'test_started' then
      -- Only clear and show title for the first test (main test run)
      if not has_started then
        has_started = true
        M.clear_buffers()
        M.show_title(data.name, data.location)
      end
    elseif event_type == 'test_finished' then
      M.show_result(data)
    end
  end
  
  storage.subscribe(storage_subscription)
end

-- Clean up panel subscription
function M.cleanup()
  if storage_subscription then
    storage.unsubscribe(storage_subscription)
    storage_subscription = nil
    has_started = false  -- Reset for next run
  end
end

-- Clear all panel buffers
function M.clear_buffers()
  for _, buf in ipairs(M.get_buffers()) do
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    M.scroll_down(buf)
  end
end

-- Show test title
function M.show_title(name, location)
  local title = name .. " (" .. location .. ")"
  for _, buf in ipairs(M.get_buffers()) do
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      title,
      "",
      "",
      "",
    })
    M.scroll_down(buf)
  end
end

-- Handle output from storage
function M.handle_output(output_data)
  local use_builtin_colorizer = require("quicktest").config.use_builtin_colorizer
  
  for _, buf in ipairs(M.get_buffers()) do
    local should_scroll = M.should_continue_scroll(buf)
    
    if output_data.type == "stdout" then
      local lines = vim.split(output_data.data, "\n")
      table.insert(lines, "")
      table.insert(lines, "")
      
      if use_builtin_colorizer then
        printer:set_next_lines(lines, buf, 2)
      else
        local line_count = vim.api.nvim_buf_line_count(buf)
        local new_lines = {}
        for i, line in ipairs(lines) do
          new_lines[i] = string.gsub(line, "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
        end
        vim.api.nvim_buf_set_lines(buf, line_count - 2, -1, false, new_lines)
      end
    elseif output_data.type == "stderr" then
      local lines = vim.split(output_data.data, "\n")
      table.insert(lines, "")
      table.insert(lines, "")
      
      if #lines > 0 then
        local line_count = vim.api.nvim_buf_line_count(buf)
        local new_lines = {}
        for i, line in ipairs(lines) do
          new_lines[i] = string.gsub(line, "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
        end
        vim.api.nvim_buf_set_lines(buf, line_count - 2, -1, false, new_lines)
        
        for i = 0, #lines - 1 do
          vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", line_count - 2 + i, 0, -1)
        end
      end
    elseif output_data.type == "status" then
      local line_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { output_data.data })
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticWarn", line_count - 1, 0, -1)
    end
    
    if should_scroll then
      M.scroll_down(buf)
    end
  end
end

-- Show test result
function M.show_result(result_data)
  local status_text = ""
  local highlight_group = ""
  
  if result_data.duration then
    local time_display = string.format("%.2f", result_data.duration / 1000) .. "s"
    if result_data.status == "passed" then
      status_text = "Passed " .. time_display
      highlight_group = "DiagnosticOk"
    elseif result_data.status == "failed" then
      status_text = "Failed " .. time_display
      highlight_group = "DiagnosticError"
    end
  end
  
  if status_text ~= "" then
    for _, buf in ipairs(M.get_buffers()) do
      local line_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { status_text })
      vim.api.nvim_buf_add_highlight(buf, -1, highlight_group, line_count - 1, 0, -1)
    end
  end
end

return M
