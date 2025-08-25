local event = require("nui.utils.autocmd").event
local Popup = require("nui.popup")
local Split = require("nui.split")
local storage = require("quicktest.storage")
local colorized_printer = require("quicktest.colored_printer")

local M = {}

local api = vim.api
local printer = colorized_printer.new()
local storage_subscription = nil
local has_started = false -- Track if we've already started

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

-- Helper function to safely write to a buffer (handles read-only buffers)
local function safe_buf_write(buf, start_line, end_line, strict_indexing, lines)
  local was_modifiable = vim.api.nvim_buf_get_option(buf, 'modifiable')
  local was_readonly = vim.api.nvim_buf_get_option(buf, 'readonly')

  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_option(buf, 'readonly', false)

  vim.api.nvim_buf_set_lines(buf, start_line, end_line, strict_indexing, lines)

  vim.api.nvim_buf_set_option(buf, 'modifiable', was_modifiable)
  vim.api.nvim_buf_set_option(buf, 'readonly', was_readonly)
end

-- Function to get or create a buffer with a specific name
local function get_or_create_buf(name)
  local full_name = "quicktest://" .. name

  local init_buf = function(buf)
    api.nvim_buf_set_name(buf, full_name)

    vim.bo[buf].undolevels = -1
    vim.bo[buf].filetype = "quicktest-output"
    vim.bo[buf].swapfile = false
    vim.bo[buf].buftype = "nofile" -- Changed to nofile - not a real file
    vim.bo[buf].bufhidden = "hide" -- Hide when not displayed
    vim.bo[buf].buflisted = false  -- Don't list in buffer list
    vim.bo[buf].modified = false   -- Start as unmodified

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
M.get_split_winid = function()
  return find_win_by_bufnr(get_split_buf())
end

local function add_autocmd(winid, buf)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    callback = function(args)
      local win = vim.fn.bufwinid(args.buf)
      if win == winid and args.buf ~= buf then
        -- Buffer is being opened in our panel window, restore the correct buffer
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_set_buf(winid, buf)
          end
        end)
        return true
      end
    end,
  })
end

local function open_popup()
  local popup_options = vim.tbl_deep_extend("force", {
    enter = false, -- Don't enter the popup window by default
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
    vim.api.nvim_win_set_option(popup.winid, 'modifiable', false)
    vim.api.nvim_win_set_option(popup.winid, 'readonly', true)

    -- Add autocmd to prevent buffer switching in this window
    add_autocmd(popup.winid, get_popup_buf())
  end
end

local function open_split()
  local split = Split({
    relative = "editor",
    position = "bottom",
    size = "30%",
    enter = false,
    focusable = false,
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

    -- Add autocmd to prevent buffer switching in this window
    add_autocmd(split.winid, get_split_buf())

    -- Check if summary should join (avoid circular dependency)
    vim.schedule(function()
      local success, ui = pcall(require, "quicktest.ui")
      if success then
        local summary = ui.get("summary")
        if summary and summary.config and summary.config.join_to_panel and summary.create_joined_split then
          summary.create_joined_split(split.winid)
        end
      end
    end)
  end
end

-- Restore buffer content from current storage state
function M.restore_buffer_content(buf)
  local output_lines = storage.get_current_output()
  local current_results = storage.get_current_results()

  if not output_lines or #output_lines == 0 then
    -- No content to restore, but check if we have test results to show
    if not current_results or #current_results == 0 then
      return
    end
  end

  -- Find the main test result for title
  local main_test = nil
  for _, result in ipairs(current_results) do
    if result.name and result.name:match("^Running test:") then
      main_test = result
      break
    end
  end

  -- Set buffer content
  local lines = {}

  -- Add title if we have a main test
  if main_test then
    table.insert(lines, main_test.name .. " (" .. (main_test.location or "") .. ")")
    table.insert(lines, "")
  end

  -- Add output lines
  for _, output_line in ipairs(output_lines) do
    if output_line.type == "stdout" or output_line.type == "stderr" then
      local content_lines = vim.split(output_line.data or "", "\n")
      for _, line in ipairs(content_lines) do
        table.insert(lines, line)
      end
    end
  end

  -- If no output but we have results, show a summary
  if #lines <= 2 and current_results and #current_results > 0 then
    for _, result in ipairs(current_results) do
      if not result.name:match("^Running test:") then -- Skip the main test entry
        local status_icon = result.status == "passed" and "✓" or
            result.status == "failed" and "✗" or
            result.status == "skipped" and "⊝" or
            result.status == "running" and "" or "○"
        table.insert(lines, status_icon .. " " .. result.name)
      end
    end
  end

  -- Add final spacing
  table.insert(lines, "")
  table.insert(lines, "")

  -- Set all lines at once using safe write
  safe_buf_write(buf, 0, -1, false, lines)

  M.scroll_down(buf)
end

local function try_open_split()
  if not M.is_split_opened() then
    open_split()
    -- Restore content after opening
    vim.schedule(function()
      M.restore_buffer_content(get_split_buf())
    end)
  end
end

local function try_open_popup()
  if not M.is_popup_opened() then
    open_popup()
    -- Restore content after opening
    vim.schedule(function()
      M.restore_buffer_content(get_popup_buf())
    end)
  end
end

---@param mode WinModeWithoutAuto
function M.try_open_win(mode)
  if mode == "popup" then
    if M.is_split_opened() then
      M.try_close_win("split") -- Close split if open
    end
    try_open_popup()
  else                         -- mode == "split"
    if M.is_popup_opened() then
      M.try_close_win("popup") -- Close popup if open
    end
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
    -- Check if summary should also be closed
    local success, summary = pcall(require, "quicktest.ui.summary")
    if success and summary.config.join_to_panel then
      summary.close()
    end
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
    has_started = false -- Reset for next run
  end
end

-- Clear all panel buffers
function M.clear_buffers()
  for _, buf in ipairs(M.get_buffers()) do
    safe_buf_write(buf, 0, -1, false, {})
    M.scroll_down(buf)
  end
end

-- Show test title
function M.show_title(name, location)
  local title = name .. " (" .. location .. ")"
  for _, buf in ipairs(M.get_buffers()) do
    safe_buf_write(buf, 0, -1, false, {
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
        safe_buf_write(buf, line_count - 2, -1, false, new_lines)
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
        safe_buf_write(buf, line_count - 2, -1, false, new_lines)

        for i = 0, #lines - 1 do
          vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", line_count - 2 + i, 0, -1)
        end
      end
    elseif output_data.type == "status" then
      local line_count = vim.api.nvim_buf_line_count(buf)
      safe_buf_write(buf, line_count - 1, line_count, false, { output_data.data })
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
      safe_buf_write(buf, line_count - 1, line_count, false, { status_text })
      vim.api.nvim_buf_add_highlight(buf, -1, highlight_group, line_count - 1, 0, -1)
    end
  end
end

return M
