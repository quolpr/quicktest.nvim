local M = {}

-- UI consumers registry
local ui_consumers = {}

-- Register a UI consumer
---@param name string
---@param consumer table
function M.register(name, consumer)
  ui_consumers[name] = consumer
  
  -- Initialize the consumer if it has an init method
  if consumer.init then
    consumer.init()
  end
end

-- Unregister a UI consumer
---@param name string
function M.unregister(name)
  local consumer = ui_consumers[name]
  if consumer and consumer.cleanup then
    consumer.cleanup()
  end
  ui_consumers[name] = nil
end

-- Get a registered UI consumer
---@param name string
---@return table?
function M.get(name)
  return ui_consumers[name]
end

-- Get all registered UI consumers
---@return table<string, table>
function M.get_all()
  return vim.deepcopy(ui_consumers)
end

-- Initialize all UI consumers
function M.init_all()
  for name, consumer in pairs(ui_consumers) do
    if consumer.init then
      consumer.init()
    end
  end
end

-- Cleanup all UI consumers
function M.cleanup_all()
  for name, consumer in pairs(ui_consumers) do
    if consumer.cleanup then
      consumer.cleanup()
    end
  end
end

-- Auto-register built-in UI consumers
local function auto_register(config)
  local panel = require("quicktest.ui.panel")
  M.register("panel", panel)
  
  -- Only register quickfix if enabled
  if not config or config.quickfix.enabled then
    local quickfix = require("quicktest.ui.quickfix")
    quickfix.config = config and config.quickfix or { enabled = true, open = true }
    M.register("quickfix", quickfix)
  end
  
  -- Only register diagnostics if enabled
  if not config or config.diagnostics.enabled then
    local diagnostics = require("quicktest.ui.diagnostics")
    diagnostics.config = config and config.diagnostics or { enabled = true }
    M.register("diagnostics", diagnostics)
  end
  
  -- Only register summary if enabled
  if not config or (config.summary and config.summary.enabled ~= false) then
    local summary = require("quicktest.ui.summary")
    summary.config = config and config.summary or { enabled = true, join_to_panel = false }
    M.register("summary", summary)
  end
  
  -- Only register status if enabled
  if not config or (config.status and config.status.enabled ~= false) then
    local status = require("quicktest.ui.status")
    status.config = config and config.status or { enabled = true, signs = true }
    M.register("status", status)
  end
end

-- Initialize the UI system with config
---@param config QuicktestConfig?
function M.init_with_config(config)
  -- Cleanup existing consumers first
  M.cleanup_all()
  
  -- Clear registry
  ui_consumers = {}
  
  -- Re-register with new config
  auto_register(config)
end

-- Initialize the UI system (backwards compatibility)
auto_register()

return M
