local M = {}

---@class TestResult
---@field name string
---@field location string
---@field status 'running' | 'passed' | 'failed'
---@field duration number?
---@field timestamp number

---@class OutputLine
---@field type 'stdout' | 'stderr' | 'status'
---@field data string
---@field timestamp number

---@class StorageState
---@field test_results TestResult[]
---@field output_lines OutputLine[]
---@field subscribers (fun(event_type: string, data: any))[]

local current_state = {
  test_results = {},
  output_lines = {},
  subscribers = {}
}

-- Emit event to all subscribers
---@param event_type string
---@param data any
local function emit_event(event_type, data)
  for _, subscriber in ipairs(current_state.subscribers) do
    pcall(subscriber, event_type, data)
  end
end

-- Clear current run state and emit run_started event
function M.clear()
  current_state.test_results = {}
  current_state.output_lines = {}
  -- Don't clear subscribers - they persist across runs
  emit_event("run_started", {})
end

-- Subscribe to storage events for current run
---@param callback fun(event_type: string, data: any)
function M.subscribe(callback)
  table.insert(current_state.subscribers, callback)
end

-- Unsubscribe from storage events
---@param callback fun(event_type: string, data: any)
function M.unsubscribe(callback)
  for i, subscriber in ipairs(current_state.subscribers) do
    if subscriber == callback then
      table.remove(current_state.subscribers, i)
      break
    end
  end
end

-- Add test start event (or update existing)
---@param name string
---@param location string
function M.test_started(name, location)
  -- Check if test already exists
  for _, result in ipairs(current_state.test_results) do
    if result.name == name then
      -- Update existing test
      if location and location ~= "" then
        result.location = location
      end
      emit_event('test_started', result)
      return
    end
  end

  -- Create new test entry
  local result = {
    name = name,
    location = location,
    status = 'running',
    duration = nil,
    timestamp = vim.uv.now()
  }

  table.insert(current_state.test_results, result)
  emit_event('test_started', result)
end

-- Add test output event
---@param type 'stdout' | 'stderr' | 'status'
---@param data string
function M.test_output(type, data)
  local output = {
    type = type,
    data = data,
    timestamp = vim.uv.now()
  }

  table.insert(current_state.output_lines, output)
  emit_event('test_output', output)
end

-- Mark test as finished
---@param name string
---@param status 'passed' | 'failed'
---@param duration number?
---@param location string?
function M.test_finished(name, status, duration, location)
  -- Find and update the test result
  for _, result in ipairs(current_state.test_results) do
    if result.name == name then
      result.status = status
      result.duration = duration and duration or result.duration
      result.location = location and location or result.location
      emit_event('test_finished', result)
      break
    end
  end
end

-- Get all test results for current run
---@return TestResult[]
function M.get_current_results()
  return vim.deepcopy(current_state.test_results)
end

-- Get all output lines for current run
---@return OutputLine[]
function M.get_current_output()
  return vim.deepcopy(current_state.output_lines)
end

-- Get current run summary
---@return {total: number, running: number, passed: number, failed: number}
function M.get_run_summary()
  local summary = {
    total = #current_state.test_results,
    running = 0,
    passed = 0,
    failed = 0
  }

  for _, result in ipairs(current_state.test_results) do
    summary[result.status] = summary[result.status] + 1
  end

  return summary
end

return M
