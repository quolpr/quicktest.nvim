local Job = require("plenary.job")
local q = require("quicktest.adapters.vitest.query")
local ts = require("quicktest.ts")
local fs = require("quicktest.fs_utils")

local M = {
  name = "vitest",
}
---@class VitestRunParams
---@field func_names string[]
---@field ns_name string
---@field test_name string
---@field cwd string
---@field bin string
---@field config_path string

local function escape_test_pattern(s)
  return (
    s:gsub("%(", "%\\(")
      :gsub("%)", "%\\)")
      :gsub("%]", "%\\]")
      :gsub("%[", "%\\[")
      :gsub("%*", "%\\*")
      :gsub("%+", "%\\+")
      :gsub("%-", "%\\-")
      :gsub("%?", "%\\?")
      :gsub("%$", "%\\$")
      :gsub("%^", "%\\^")
      :gsub("%/", "%\\/")
  )
end

local vitest_config_pattern = fs.root_pattern("{vite,vitest}.config.{js,ts,mjs,mts}")
---@param path string
---@return string|nil
local function get_vitest_config(path)
  local rootPath = vitest_config_pattern(path)

  if not rootPath then
    return nil
  end

  -- Ordered by config precedence (https://vitest.dev/config/#configuration)
  local possibleVitestConfigNames = {
    "vitest.config.ts",
    "vitest.config.js",
    "vite.config.ts",
    "vite.config.js",
    -- `.mts,.mjs` are sometimes needed (https://vitejs.dev/guide/migration.html#deprecate-cjs-node-api)
    "vitest.config.mts",
    "vitest.config.mjs",
    "vite.config.mts",
    "vite.config.mjs",
  }

  for _, configName in ipairs(possibleVitestConfigNames) do
    local configPath = fs.path.join(rootPath, configName)

    if fs.path.exists(configPath) then
      return configPath
    end
  end

  return nil
end

---@param cwd string
local function find_bin(cwd)
  while cwd and #cwd > 1 do
    local bin = fs.path.join(cwd, "node_modules", ".bin", "vitest")

    if fs.path.exists(bin) then
      return bin
    end

    cwd = vim.fn.fnamemodify(cwd, ":h")
  end

  return nil
end

local function find_cwd(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file

  return fs.find_ancestor_of_file(path, "package.json")
end

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@return VitestRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos)
  local cwd = find_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = find_bin(cwd)

  if not bin then
    return nil, "Failed to find vitest binary"
  end

  local params = {
    ns_name = ts.get_current_test_name(q, bufnr, cursor_pos, "namespace"),
    test_name = ts.get_current_test_name(q, bufnr, cursor_pos, "test"),
    cwd = cwd,
    bin = bin,
    config_path = get_vitest_config(cwd) or "vitest.config.js",
    -- Add other parameters as need ЖСd
  }
  return params, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return VitestRunParams | nil, string | nil
---@diagnostic disable-next-line: unused-local
M.build_file_run_params = function(bufnr, cursor_pos)
  local cwd = find_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = find_bin(cwd)

  if not bin then
    return nil, "Failed to find vitest binary"
  end

  local params = {
    cwd = cwd,
    bin = bin,
    config_path = get_vitest_config(cwd) or "vitest.config.js",
    -- Add other parameters as needed
  }

  return params, nil
end

---@param params VitestRunParams
local function build_args(params)
  local args = {}

  if fs.path.exists(params.config_path) then
    -- only use config if available
    table.insert(args, "--config=" .. params.config_path)
  end

  local test_name_pattern = ".*"
  if params.ns_name ~= "" and params.ns_name ~= nil then
    test_name_pattern = "^ " .. escape_test_pattern(params.ns_name)
  end

  if params.test_name ~= "" and params.test_name ~= nil then
    test_name_pattern = escape_test_pattern(params.test_name) .. "$"
  end

  vim.list_extend(args, {
    "--watch=false",
    "--silent=false",
    "--reporter=verbose",
    "--color",
    "--testNamePattern=" .. test_name_pattern,
  })

  return args
end

--- Executes the test with the given parameters.
---@param params VitestRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local args = build_args(params)

  local job = Job:new({
    command = params.bin,
    args = args, -- Modify based on how your test command needs to be structured
    cwd = params.cwd,
    on_stdout = function(_, data)
      for k, v in pairs(vim.split(data, "\n")) do
        send({ type = "stdout", output = v })
      end
    end,
    on_stderr = function(_, data)
      for k, v in pairs(vim.split(data, "\n")) do
        send({ type = "stderr", output = v })
      end
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()

  return job.pid
end

-- ---@param params VitestRunParams
-- M.title = function(params)
--   local args = build_args(params)
--
--   return "Running test: " .. table.concat({ unpack(args, 2) }, " ")
-- end

-- --- Handles actions to take after the test run, based on the results.
-- ---@param params any
-- ---@param results any
-- M.after_run = function(params, results)
--   -- Implement actions based on the results, such as updating UI or handling errors
-- end

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  local is_test_file = false

  if string.match(file_path, "__tests__") then
    is_test_file = true
  end

  for _, x in ipairs({ "spec", "test" }) do
    for _, ext in ipairs({ "js", "jsx", "coffee", "ts", "tsx" }) do
      if string.match(file_path, "%." .. x .. "%." .. ext .. "$") then
        is_test_file = true
        goto matched_pattern
      end
    end
  end
  ::matched_pattern::
  return is_test_file
end

return M
