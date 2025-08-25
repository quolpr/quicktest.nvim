local M = {}

---@class TestResult
---@field name string
---@field location string
---@field status 'running' | 'passed' | 'failed' | 'skipped'
---@field duration number?
---@field timestamp number
---@field assert_failures AssertFailure[]?

---@class AssertFailure
---@field full_path string
---@field line number
---@field message string
---@field error_message string?

---@class OutputLine
---@field type 'stdout' | 'stderr' | 'status'
---@field data string
---@field timestamp number

---@class StorageState
---@field test_results TestResult[]
---@field output_lines OutputLine[]
---@field subscribers (fun(event_type: string, data: any))[]
---@field failed_test_index number
---@field cached_failed_tests TestResult[]?

local current_state = {
  test_results = {},
  output_lines = {},
  subscribers = {},
  failed_test_index = 0,
  cached_failed_tests = nil
}

-- Emit event to all subscribers
---@param event_type string
---@param data any
local function emit_event(event_type, data)
  for _, subscriber in ipairs(current_state.subscribers) do
    pcall(subscriber, event_type, data)
  end
end

-- Invalidate cached failed tests when test status changes
local function invalidate_failed_tests_cache()
  current_state.cached_failed_tests = nil
  current_state.failed_test_index = 0
end

-- Clear current run state and emit run_started event
function M.clear()
  current_state.test_results = {}
  current_state.output_lines = {}
  current_state.failed_test_index = 0
  current_state.cached_failed_tests = nil
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
---@param status 'passed' | 'failed' | 'skipped'
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

  -- Invalidate cache when test statuses change
  invalidate_failed_tests_cache()
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
-- Add assert failure information to a test
---@param test_name string
---@param full_path string
---@param line number
---@param message string
function M.assert_failure(test_name, full_path, line, message)
  -- Look for existing test
  local found_result = nil
  for _, result in ipairs(current_state.test_results) do
    if result.name == test_name then
      found_result = result
      break
    end
  end

  -- If test doesn't exist, create it
  if not found_result then
    found_result = {
      name = test_name,
      location = full_path .. ":" .. line, -- Use assert location as test location
      status = 'running',
      duration = nil,
      timestamp = vim.uv.now(),
      assert_failures = {}
    }
    table.insert(current_state.test_results, found_result)
    emit_event('test_started', found_result)
  end

  -- Now add the assert failure to the test
  if not found_result.assert_failures then
    found_result.assert_failures = {}
  end

  -- Check if we already have a failure at this location
  local existing = nil
  for _, failure in ipairs(found_result.assert_failures) do
    if failure.full_path == full_path and failure.line == line then
      existing = failure
      break
    end
  end

  if existing then
    -- Update existing failure
    existing.message = message
  else
    -- Add new failure
    table.insert(found_result.assert_failures, {
      full_path = full_path,
      line = line,
      message = message
    })
  end

  emit_event('assert_failure', {
    test_name = test_name,
    full_path = full_path,
    line = line,
    message = message
  })
end

-- Update assert failure error message for the latest failure of a test
---@param test_name string
---@param error_message string
function M.assert_error(test_name, error_message)
  for _, result in ipairs(current_state.test_results) do
    if result.name == test_name and result.assert_failures and #result.assert_failures > 0 then
      -- Update the error_message of the most recent assert failure
      local latest_failure = result.assert_failures[#result.assert_failures]
      latest_failure.error_message = error_message

      emit_event('assert_error', {
        test_name = test_name,
        error_message = error_message,
        full_path = latest_failure.full_path,
        line = latest_failure.line
      })
      return
    end
  end
end

-- Update assert failure message for the latest failure of a test
---@param test_name string
---@param message string
function M.assert_message(test_name, message)
  for _, result in ipairs(current_state.test_results) do
    if result.name == test_name and result.assert_failures and #result.assert_failures > 0 then
      -- Update the message of the most recent assert failure
      local latest_failure = result.assert_failures[#result.assert_failures]
      latest_failure.message = message

      emit_event('assert_message', {
        test_name = test_name,
        message = message,
        full_path = latest_failure.full_path,
        line = latest_failure.line
      })
      return
    end
  end
end

---@return {total: number, running: number, passed: number, failed: number, skipped: number}
function M.get_run_summary()
  local summary = {
    total = #current_state.test_results,
    running = 0,
    passed = 0,
    failed = 0,
    skipped = 0
  }

  for _, result in ipairs(current_state.test_results) do
    summary[result.status] = summary[result.status] + 1
  end

  return summary
end

-- Get failed test results with caching
local function get_failed_tests()
  -- Return cached version if available
  if current_state.cached_failed_tests then
    return current_state.cached_failed_tests
  end

  -- Build and cache failed tests list, filter out tests with invalid locations
  local failed_tests = {}
  for _, result in ipairs(current_state.test_results) do
    if result.status == 'failed' then
      -- Only include tests that have valid locations (line > 0) or no location (will be discovered)
      local has_valid_location = false
      if not result.location or result.location == "" then
        has_valid_location = true -- Will be discovered by summary logic
      else
        local parts = vim.split(result.location, ":")
        local line = tonumber(parts[2]) or 0
        if line > 0 then
          has_valid_location = true
        end
      end
      
      if has_valid_location then
        table.insert(failed_tests, result)
      end
    end
  end

  current_state.cached_failed_tests = failed_tests
  return failed_tests
end

-- Navigate to next failed test
---@return TestResult?
function M.next_failed_test()
  local failed_tests = get_failed_tests()
  if failed_tests == nil or #failed_tests == 0 then
    return nil
  end

  current_state.failed_test_index = current_state.failed_test_index + 1
  if current_state.failed_test_index > #failed_tests then
    current_state.failed_test_index = 1
  end

  return failed_tests[current_state.failed_test_index]
end

-- Navigate to previous failed test
---@return TestResult?
function M.prev_failed_test()
  local failed_tests = get_failed_tests()
  if failed_tests == nil or #failed_tests == 0 then
    return nil
  end

  current_state.failed_test_index = current_state.failed_test_index - 1
  if current_state.failed_test_index < 1 then
    current_state.failed_test_index = #failed_tests
  end

  return failed_tests[current_state.failed_test_index]
end

return M
