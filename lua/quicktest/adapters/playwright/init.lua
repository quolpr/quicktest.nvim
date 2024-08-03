local Job = require("plenary.job")
local q = require("quicktest.adapters.playwright.query")
local ts = require("quicktest.ts")
local fs = require("quicktest.fs_utils")

---@class PlaywrightAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field config_path (fun(bufnr: integer, current: string): string)?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?

local M = {
  name = "playwright",
  ---@type PlaywrightAdapterOptions
  options = {},
}

---@class PlaywrightRunParams
---@field bufnr integer
---@field func_names string[]
---@field ns_name string
---@field test_name string
---@field cwd string
---@field bin string
---@field config_path string
---@field file string
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
  )
end

local playwright_config_pattern = fs.root_pattern("{playwright}.config.{js,ts,mjs,mts}")

---@param path string
---@return string|nil
local function get_playwright_config(path)
  local rootPath = playwright_config_pattern(path)

  if not rootPath then
    return nil
  end

  local possiblePlaywrightConfigNames = {
    "playwright.config.ts",
    "playwright.config.js",
    "playwright.config.mts",
    "playwright.config.mjs",
  }

  for _, configName in ipairs(possiblePlaywrightConfigNames) do
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
    local bin = fs.path.join(cwd, "node_modules", ".bin", "playwright")

    if fs.path.exists(bin) then
      return bin
    end

    cwd = vim.fn.fnamemodify(cwd, ":h")
  end

  return nil
end

local function find_cwd(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)
  local path = vim.fn.fnamemodify(buffer_name, ":p:h")

  return fs.find_ancestor_of_file(path, "package.json")
end

---@param bufnr integer
---@return string
M.get_cwd = function(bufnr)
  local current = find_cwd(bufnr)

  return M.options.cwd and M.options.cwd(bufnr, current) or current
end

---@param bufnr integer
---@param cwd string
---@return string | nil
M.get_bin = function(bufnr, cwd)
  local current = find_bin(cwd)

  return M.options.bin and M.options.bin(bufnr, current) or current
end

---@param bufnr integer
---@param cwd string
---@return string
M.get_config_path = function(bufnr, cwd)
  local current = get_playwright_config(cwd) or "playwright.config.js"

  return M.options.config_path and M.options.config_path(bufnr, current) or current
end

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return PlaywrightRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(bufnr, cwd)
  if not bin then
    return nil, "Failed to find playwright binary"
  end

  local config_path = M.get_config_path(bufnr, cwd)
  local file = vim.api.nvim_buf_get_name(bufnr)

  local params = {
    bufnr = bufnr,
    ns_name = ts.get_current_test_name(q, bufnr, cursor_pos, "namespace"),
    test_name = ts.get_current_test_name(q, bufnr, cursor_pos, "test"),
    file = file,
    cwd = cwd,
    bin = bin,
    config_path = config_path,
    opts = opts,
  }
  return params, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return PlaywrightRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(bufnr, cwd)
  if not bin then
    return nil, "Failed to find playwright binary"
  end

  local config_path = M.get_config_path(bufnr, cwd)

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
---@return PlaywrightRunParams | nil, string | nil
---@diagnostic disable-next-line: unused-local
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(bufnr, cwd)
  if not bin then
    return nil, "Failed to find playwright binary"
  end

  local config_path = M.get_config_path(bufnr, cwd)
  local file = vim.api.nvim_buf_get_name(bufnr)

  local params = {
    bufnr = bufnr,
    cwd = cwd,
    bin = bin,
    config_path = config_path,
    file = file,
    opts = opts,
  }

  return params, nil
end

---@param params PlaywrightRunParams
local function build_args(params)
  local args = { "test" }

  local test_name_pattern = ""
  if params.ns_name ~= "" and params.ns_name ~= nil then
    test_name_pattern = escape_test_pattern(params.ns_name)
  end

  if params.test_name ~= "" and params.test_name ~= nil then
    if test_name_pattern ~= "" then
      test_name_pattern = test_name_pattern .. " "
    else
      test_name_pattern = " "
    end
    test_name_pattern = test_name_pattern .. escape_test_pattern(params.test_name)
  end

  local file = nil
  if params.file ~= "" and params.file ~= nil then
    file = params.file
  end

  if fs.path.exists(params.config_path) then
    -- only use config if available
    table.insert(args, "--config=" .. params.config_path)
  end
  if test_name_pattern ~= "" then
    vim.list_extend(args, { "-g", test_name_pattern })
  end
  vim.list_extend(args, { file })

  return args
end

--- Executes the test with the given parameters.
---@param params PlaywrightRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local args = build_args(params)

  args = params.opts.additional_args and vim.list_extend(args, params.opts.additional_args) or args
  args = M.options.args and M.options.args(params.bufnr, args) or args

  local env = vim.fn.environ()
  env = M.options.env and M.options.env(params.bufnr, env) or env

  local job = Job:new({
    command = params.bin,
    args = args,
    cwd = params.cwd,
    env = env,
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
    return is_test_file
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

--- Adapter options.
setmetatable(M, {
  __call = function(_, opts)
    M.options = opts
    return M
  end,
})

return M
