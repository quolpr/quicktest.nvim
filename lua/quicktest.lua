-- main module file
local module = require("quicktest.module")

local config = {
  adapters = {},
  ui = {}, -- List of UI consumers
  strategy = "default",
}

---@class MyModule
local M = {}

--- @type QuicktestConfig
M.config = config

---@param args QuicktestConfig?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Initialize UI with explicit consumers
  local ui = require("quicktest.ui")
  ui.init_with_consumers(M.config.ui or {})
end

M.current_win_mode = function()
  local ui = require("quicktest.ui")
  local panel = ui.get("panel")
  local default_win_mode = panel and panel.config.default_win_mode or "split"
  return module.current_win_mode(default_win_mode)
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

-- Summary window controls
M.open_summary = function()
  local ui = require("quicktest.ui")
  local summary = ui.get("summary")
  if summary then
    summary.open()
  end
end

M.close_summary = function()
  local ui = require("quicktest.ui")
  local summary = ui.get("summary")
  if summary then
    summary.close()
  end
end

M.toggle_summary = function()
  local ui = require("quicktest.ui")
  local summary = ui.get("summary")
  if summary then
    summary.toggle()
  end
end

M.toggle_summary_failed_filter = function()
  local ui = require("quicktest.ui")
  local summary = ui.get("summary")
  if summary and summary.toggle_failed_filter then
    summary.toggle_failed_filter()
  end
end

-- Navigate to next failed test
M.next_failed_test = function()
  local storage = require("quicktest.storage")
  local test = storage.next_failed_test()
  if not test then
    vim.notify("No failed tests found", vim.log.levels.INFO)
    return
  end

  local navigation = require("quicktest.navigation")
  navigation.jump_to_test(test)
end

-- Navigate to previous failed test
M.prev_failed_test = function()
  local storage = require("quicktest.storage")
  local test = storage.prev_failed_test()
  if not test then
    vim.notify("No failed tests found", vim.log.levels.INFO)
    return
  end

  local navigation = require("quicktest.navigation")
  navigation.jump_to_test(test)
end

return M
