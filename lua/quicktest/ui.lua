local event = require("nui.utils.autocmd").event
local Popup = require("nui.popup")
local Split = require("nui.split")

local M = {}

local api = vim.api

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

-- Function to get or create a buffer with a specific name
local function get_or_create_buf(name)
  local full_name = "quicktest://" .. name

  -- Find buffer with name if it exists
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local buf_name = api.nvim_buf_get_name(buf)
    if buf_name == full_name then
      return buf
    end
  end

  -- Create new buffer if not found
  local buf = api.nvim_create_buf(false, false)
  api.nvim_buf_set_name(buf, full_name)
  vim.bo[buf].undolevels = -1
  vim.bo[buf].filetype = "quicktest-output"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].buftype = "nowrite" -- Buffer that cannot be written
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
    enter = true,
    bufnr = get_popup_buf(),
    focusable = true,
    border = {
      style = "rounded",
    },
    position = "50%",
    size = {
      width = "80%",
      height = "60%",
    },
  }, require("quicktest").config.popup_options)

  Popup(popup_options):mount()
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

return M
