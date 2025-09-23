-- main module file
local module = require("quicktest.module")

---@type QuicktestConfig
local config = {
  adapters = {},
  default_win_mode = "split",
  use_builtin_colorizer = true,
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

---@class Quicktest
local M = {}

--- @type QuicktestConfig
M.config = config

---@param args? QuicktestConfig
function M.setup(args)
  args = args or {}
  M.config = vim.tbl_deep_extend("force", M.config, args)
end

function M.current_win_mode()
  return module.current_win_mode(M.config.default_win_mode)
end

--- @param mode WinModeWithoutAuto
function M.open_win(mode)
  return module.try_open_win(mode)
end

--- @param mode WinModeWithoutAuto
function M.close_win(mode)
  return module.try_close_win(mode)
end

--- @param mode WinModeWithoutAuto
function M.toggle_win(mode)
  return module.toggle_win(mode)
end

--- @param mode? WinMode
function M.run_previous(mode)
  mode = mode or "auto"
  return module.run_previous(M.config, mode)
end

--- @param mode? WinMode
--- @param adapter? Adapter
--- @param opts? AdapterRunOpts
function M.run_line(mode, adapter, opts)
  mode = mode or "auto"
  adapter = adapter or "auto"
  opts = opts or {}
  return module.prepare_and_run(M.config, "line", mode, adapter, opts)
end

--- @param mode? WinMode
--- @param adapter? Adapter
--- @param opts? AdapterRunOpts
function M.run_file(mode, adapter, opts)
  mode = mode or "auto"
  adapter = adapter or "auto"
  opts = opts or {}
  return module.prepare_and_run(M.config, "file", mode, adapter, opts)
end

--- @param mode? WinMode
--- @param adapter? Adapter
--- @param opts? AdapterRunOpts
function M.run_dir(mode, adapter, opts)
  mode = mode or "auto"
  adapter = adapter or "auto"
  opts = opts or {}
  return module.prepare_and_run(M.config, "dir", mode, adapter, opts)
end

--- @param mode? WinMode
--- @param adapter? Adapter
--- @param opts? AdapterRunOpts
function M.run_all(mode, adapter, opts)
  mode = mode or "auto"
  adapter = adapter or "auto"
  opts = opts or {}
  return module.prepare_and_run(M.config, "all", mode, adapter, opts)
end

function M.cancel_current_run()
  module.kill_current_run()
end

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
