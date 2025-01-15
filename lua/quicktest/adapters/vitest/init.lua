local Job = require("plenary.job")
local q = require("quicktest.adapters.vitest.query")
local ts = require("quicktest.ts")
local fs = require("quicktest.fs_utils")

---@class VitestAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field config_path (fun(bufnr: integer, current: string): string)?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?

local M = {
  name = "vitest",
  ---@type VitestAdapterOptions
  options = {},
}

---@class VitestRunParams
---@field bufnr integer
---@field file string?
---@field ns_name string
---@field test_name string
---@field cwd string
---@field bin string
---@field config_path string
---@field opts AdapterRunOpts

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
      :gsub("%%s", ".*") -- Match `test.each([...])("Test %s", ...)`
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

---@param bufnr integer
---@return string?
M.get_cwd = function(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file
  local detected_cwd = fs.find_ancestor_of_file(path, "package.json")

  return M.options.cwd and M.options.cwd(bufnr, detected_cwd) or detected_cwd
end

---@param cwd string
---@param bufnr integer
---@return string?
M.get_config_path = function(cwd, bufnr)
  local detected_path = get_vitest_config(cwd) or "vitest.config.js"

  return M.options.config_path and M.options.config_path(bufnr, detected_path) or detected_path
end

---@param cwd string
---@param bufnr integer
---@return string?
M.get_bin = function(cwd, bufnr)
  local detected_bin = find_bin(cwd)

  return M.options.bin and M.options.bin(bufnr, detected_bin) or detected_bin
end

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return VitestRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(cwd, bufnr)

  if not bin then
    return nil, "Failed to find vitest binary"
  end

  local config_path = M.get_config_path(cwd, bufnr)

  local file = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path

  local params = {
    bufnr = bufnr,
    ns_name = ts.get_current_test_name(q, bufnr, cursor_pos, "namespace"),
    test_name = ts.get_current_test_name(q, bufnr, cursor_pos, "test"),
    file = file,
    cwd = cwd,
    bin = bin,
    config_path = config_path,
    opts = opts,
    -- Add other parameters as needed
  }
  return params, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return VitestRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(cwd, bufnr)

  if not bin then
    return nil, "Failed to find vitest binary"
  end

  local config_path = M.get_config_path(cwd, bufnr)

  local params = {
    bufnr = bufnr,
    cwd = cwd,
    bin = bin,
    config_path = config_path,
    opts = opts,
    -- Add other parameters as needed
  }
  return params, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return VitestRunParams | nil, string | nil
---@diagnostic disable-next-line: unused-local
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(cwd, bufnr)

  if not bin then
    return nil, "Failed to find vitest binary"
  end

  local config_path = M.get_config_path(cwd, bufnr)

  local file = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path

  local params = {
    bufnr = bufnr,
    cwd = cwd,
    bin = bin,
    config_path = config_path,
    file = file,
    opts = opts,
    -- Add other parameters as needed
  }

  return params, nil
end

---@param params VitestRunParams
local function build_args(params)
  local args = {}
  local file = nil

  if fs.path.exists(params.config_path) then
    -- only use config if available
    table.insert(args, "--config=" .. params.config_path)
  end

  local test_name_pattern = ""
  if params.ns_name ~= "" and params.ns_name ~= nil then
    test_name_pattern = "^ " .. escape_test_pattern(params.ns_name)
  end

  if params.test_name ~= "" and params.test_name ~= nil then
    if test_name_pattern ~= "" then
      test_name_pattern = test_name_pattern .. " "
    else
      test_name_pattern = "^ "
    end
    test_name_pattern = test_name_pattern .. escape_test_pattern(params.test_name) .. "$"
  else
    if test_name_pattern ~= "" then
      test_name_pattern = test_name_pattern .. " .*$"
    end
  end

  if test_name_pattern == "" then
    test_name_pattern = ".*"
  end

  if params.file ~= "" and params.file ~= nil then
    file = params.file
  end

  vim.list_extend(args, {
    "--watch=false",
    "--silent=false",
    "--reporter=verbose",
    "--color",
    "--testNamePattern",
    test_name_pattern,
    file,
  })

  return args
end

--- Executes the test with the given parameters.
---@param params VitestRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local args = build_args(params)
  local env = vim.fn.environ()

  args = params.opts.additional_args and vim.list_extend(args, params.opts.additional_args) or args
  args = M.options.args and M.options.args(params.bufnr, args) or args
  env = M.options.env and M.options.env(params.bufnr, env) or env

  local job = Job:new({
    command = params.bin,
    args = args, -- Modify based on how your test command needs to be structured
    env = env,
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

  ---@type integer
  ---@diagnostic disable-next-line: assign-type-mismatch
  local pid = job.pid

  return pid
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
---@param type RunType
---@return boolean
M.is_enabled = function(bufnr, type)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local is_test_file = false

  if type == "line" or type == "file" then
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
  else
    is_test_file = vim.endswith(file_path, ".ts")
      or vim.endswith(file_path, ".js")
      or vim.endswith(file_path, ".tsx")
      or vim.endswith(file_path, ".jsx")
  end

  if M.options.is_enabled == nil then
    return is_test_file
  end

  return M.options.is_enabled(bufnr, type, is_test_file)
end

--- A helper function that uses Treesitter to determine whether the current
--- buffer imports from the package "vitest" or the `package` passed in.
--- Use this together with `is_enabled` to filter non-vitest tests if
--- you use this adapter together with other JS/TS adapters like `playwright`.
---@param bufnr integer
---@param package string?
---@return boolean
M.imports_from_vitest = function(bufnr, package)
  if package == nil then
    package = "vitest"
  end
  local expr = [[
      ((import_statement
        source: (string) @source (#contains? @source "]] .. package .. [[")
      ))
    ]]
  return ts.matches(expr, bufnr)
end

--- Adapter options.
setmetatable(M, {
  ---@param opts GoAdapterOptions
  __call = function(_, opts)
    M.options = opts

    return M
  end,
})

return M
