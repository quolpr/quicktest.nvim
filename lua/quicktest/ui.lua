local event = require("nui.utils.autocmd").event
local Popup = require("nui.popup")
local Split = require("nui.split")

local M = {}

local api = vim.api

local split_buf = api.nvim_create_buf(false, true)
local popup_buf = api.nvim_create_buf(false, true)

vim.api.nvim_buf_set_option(split_buf, "undolevels", -1)
vim.api.nvim_buf_set_option(popup_buf, "undolevels", -1)

vim.api.nvim_buf_set_option(split_buf, "filetype", "quicktest-output")
vim.api.nvim_buf_set_option(popup_buf, "filetype", "quicktest-output")

--- @type NuiSplit | nil
local split
--- @type NuiPopup | nil
local popup

M.buffers = { split_buf, popup_buf }
M.is_split_opened = false
M.is_popup_opened = false

local function open_popup()
  popup = Popup({
    enter = true,
    bufnr = popup_buf,
    focusable = true,
    border = {
      style = "rounded",
    },
    position = "50%",
    size = {
      width = "80%",
      height = "60%",
    },
  })

  popup:on(event.WinClosed, function()
    M.is_popup_opened = false

    popup = nil
  end, { once = true })

  popup:mount()

  M.is_popup_opened = true

  return popup
end

local function open_split()
  split = Split({
    relative = "editor",
    position = "bottom",
    size = "30%",
    enter = false,
  })
  split.bufnr = split_buf

  split:on(event.WinClosed, function()
    M.is_split_opened = false
  end, { once = true })

  -- mount/open the component
  split:mount()

  vim.api.nvim_win_set_option(split.winid, "statusline", "")
  vim.api.nvim_win_set_option(split.winid, "laststatus", 0)

  M.is_split_opened = true

  return split
end

local function try_open_split()
  if not M.is_split_opened then
    open_split()
  end
end

local function try_open_popup()
  if not M.is_popup_opened then
    open_popup()
  end
end

----@param mode win_mode
function M.try_open_win(mode)
  if mode == "popup" then
    try_open_popup()
  else
    try_open_split()
  end
end

----@param mode win_mode
function M.try_close_win(mode)
  if mode == "popup" then
    if popup then
      popup:hide()
    end
  else
    if split then
      split:hide()
    end
  end
end

--- @param buf number
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
