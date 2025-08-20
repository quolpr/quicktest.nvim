local M = {}

---@param msg string
---@param level number
local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level, { title = "Quicktest" })
  end)
end

---@param msg string
function M.warn(msg)
  notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
  notify(msg, vim.log.levels.INFO)
end

return M
