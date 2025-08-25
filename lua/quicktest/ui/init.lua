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

-- Initialize the UI system with explicit consumers
---@param ui_consumers_list table[]
function M.init_with_consumers(ui_consumers_list)
  -- Cleanup existing consumers first
  M.cleanup_all()

  -- Clear registry
  ui_consumers = {}

  -- Register provided consumers using their name property
  for _, consumer in ipairs(ui_consumers_list or {}) do
    if not consumer.name then
      return vim.notify("every registered consumer must have a name", vim.log.levels.ERROR)
    end
    M.register(consumer.name, consumer)
  end
end

return M
