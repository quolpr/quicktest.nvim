-- main module file
local module = require("quicktest.module")

local config = {
  adapters = {},
  default_win_mode = "split",
  use_builtin_colorizer = true,
  strategy = "default",
  popup_options = {
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
    },
    position = "50%",
    size = {
      width = "80%",
      height = "60%",
    },
  },
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
  return module.current_win_mode(M.config.default_win_mode)
end

--- @param mode WinModeWithoutAuto
M.open_win = function(mode)
  return module.try_open_win(mode)
end

--- @param mode WinModeWithoutAuto
M.close_win = function(mode)
  return module.try_close_win(mode)
end

--- @param mode WinModeWithoutAuto
M.toggle_win = function(mode)
  return module.toggle_win(mode)
end

--- @param mode WinMode?
M.run_previous = function(mode)
  return module.run_previous(M.config, mode or "auto")
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_line = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "line", mode or "auto", adapter or "auto", opts or {})
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_file = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "file", mode or "auto", adapter or "auto", opts or {})
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_dir = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "dir", mode or "auto", adapter or "auto", opts or {})
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_all = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "all", mode or "auto", adapter or "auto", opts or {})
end

M.cancel_current_run = function()
  module.kill_current_run()
end

return M
