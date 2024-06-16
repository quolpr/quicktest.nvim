-- main module file
local module = require("quicktest.module")

local config = {
  plugins = { require("quicktest.adapters.golang") },
}

---@class MyModule
local M = {}

--- @type QuicktestConfig
M.config = config

---@param args QuicktestConfig?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

M.current_win_mode = function()
  return module.current_win_mode()
end

--- @param mode WinMode
M.open_win = function(mode)
  return module.try_open(mode)
end

--- @param mode WinMode?
M.close_win = function(mode)
  return module.try_close(mode)
end

--- @param mode WinMode?
M.toggle_win = function(mode)
  return module.toggle_win(mode)
end

--- @param mode WinMode?
M.run_previous = function(mode)
  return module.run_previous(mode)
end

--- @param mode WinMode?
M.run_file = function(mode)
  return module.run_file(M.config, mode)
end

--- @param mode WinMode?
M.run_line = function(mode)
  return module.run_line(M.config, mode)
end

-- M.open("split")
-- module.run(require("quicktest.adapters.golang"), {
--   func_names = { "TestSum" },
--   sub_func_names = {},
--   cwd = "/Users/quolpr/.config/nvim/go_test",
--   module = "./abc",
--   bufnr = 0,
-- })
-- M.run(api.nvim_get_current_buf(), { "TestSum" }, nil, "/Users/quolpr/.config/nvim/go_test", "./abc")
-- require("plenary.reload").reload_module("quicktest", false)

return M
