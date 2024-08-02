local Job = require("plenary.job")
local ts = require("quicktest.ts")

---@class DartAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?

local custom_test_method_names = {}

local function find_project_directory(filepath)
  local function file_exists(path)
    local file = io.open(path, "r")
    if file then
      file:close()
      return true
    else
      return false
    end
  end

  local function find_pubspec_yaml(dir)
    local parent_dir = vim.fn.fnamemodify(dir, ":h")
    local pubspec_path = parent_dir .. "/pubspec.yaml"
    if file_exists(pubspec_path) then
      return parent_dir
    elseif parent_dir ~= dir then
      return find_pubspec_yaml(parent_dir)
    else
      return nil
    end
  end

  return find_pubspec_yaml(vim.fn.expand(filepath))
end

local function ltrim(s)
  return s:gsub("^%s*", "")
end

local function get_nearest_test(bufnr, cursor_pos)
  local function remove_dollar_signs(str)
    local pattern = "(\\?%$)(%a)"

    local result = str:gsub(pattern, function(dollar, char)
      if dollar == "\\" then
        return dollar .. char
      else
        return char
      end
    end)

    return result
  end

  local function clean_name(s)
    local extracted = s:match('"([^"]+)"')
    if extracted then
      return remove_dollar_signs(extracted)
    end
    extracted = s:match("'([^']+)'")
    if extracted then
      return remove_dollar_signs(extracted)
    end
    return ""
  end

  for pos = cursor_pos[1], 1, -1 do
    local aline = vim.api.nvim_buf_get_lines(bufnr, pos - 1, pos, true)[1]
    local line = ltrim(aline)
    if vim.startswith(line, "test(") or vim.startswith(line, "group(") then
      return clean_name(line)
    end
  end

  local names = vim.tbl_map(function(name)
    return '"' .. name .. '"'
  end, custom_test_method_names)
  local names_string = table.concat(names, " ")
  local query = [[
  ;; group blocks
  (expression_statement
    (identifier) @group (#eq? @group "group")
    (selector (argument_part (arguments . (argument (_) @namespace.name )))))
    @namespace.definition

  ;; tests blocks
  (expression_statement
    (identifier) @testFunc (#any-of? @testFunc "test" "testWidgets" ]] .. names_string .. [[)
    (selector (argument_part (arguments (argument (string_literal) @test.name)))))
    @test.definition
  ]]

  local test_name = ts.get_current_test_name(query, bufnr, cursor_pos, "test")
  local group_name = ts.get_current_test_name(query, bufnr, cursor_pos, "namespace")

  local name = nil
  if test_name then
    name = test_name
  elseif group_name then
    name = group_name
  end

  if name then
    return clean_name(name)
  end

  return ""
end

local M = {
  name = "dart",
  ---@type DartAdapterOptions
  options = {},
}
---@class DartRunParams
---@field func_name? string
---@field bufnr integer
---@field cursor_pos integer[]
---@field path string
---@field cwd string

--- @param bufnr integer
--- @return string | nil
M.get_cwd = function(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local cwd = find_project_directory(filepath)

  return M.options.cwd and M.options.cwd(bufnr, cwd) or cwd
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_line_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local cwd = M.get_cwd(bufnr)
  if cwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end

  local testname = get_nearest_test(bufnr, cursor_pos)
  if #testname == 0 then
    return nil, "No test to run"
  end

  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    func_name = testname,
    path = filepath,
    cwd = cwd,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_file_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local cwd = M.get_cwd(bufnr)
  if cwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end

  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    path = filepath,
    cwd = cwd,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_dir_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local cwd = M.get_cwd(bufnr)
  if cwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end

  local folder = vim.fn.fnamemodify(filepath, ":h")
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    path = folder,
    cwd = cwd,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_all_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local cwd = M.get_cwd(bufnr)
  if cwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end

  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    path = "",
    cwd = cwd,
  }, nil
end

---@param params DartRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local args = {}
  table.insert(args, "test")
  if #params.path > 0 then
    table.insert(args, params.path)
  end
  if params.func_name and #params.func_name > 0 then
    table.insert(args, "--plain-name=" .. params.func_name)
  end
  table.insert(args, "-r")
  table.insert(args, "github")

  args = M.options.args and M.options.args(params.bufnr, args) or args

  local bin = "flutter"
  bin = M.options.bin and M.options.bin(params.bufnr, bin) or bin

  local env = vim.fn.environ()
  env = M.options.env and M.options.env(params.bufnr, env) or env

  local job = Job:new({
    command = bin,
    args = args,
    cwd = params.cwd,
    env = env,
    on_stdout = function(_, data)
      send({ type = "stdout", raw = data, output = data })
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", rwa = data, output = data })
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

---@param params DartRunParams
M.title = function(params)
  local test_path = ""
  if params.path and #params.path > 0 then
    test_path = params.path:gsub("^" .. params.cwd, "")
    test_path = test_path:gsub("^/", "")
  end
  if #test_path == 0 then
    return "Running all"
  end
  local title = "Running dir: " .. test_path
  if test_path:sub(-#".dart") == ".dart" then
    title = "Running file: " .. test_path
  end
  if params.func_name and #params.func_name > 0 then
    return title .. ":" .. params.func_name
  end
  return title
end

---@param bufnr integer
---@param type RunType
---@return boolean
M.is_enabled = function(bufnr, type)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local is_test_file = vim.endswith(bufname, "_test.dart") or vim.endswith(bufname, ".dart")

  return M.options.is_enabled and M.options.is_enabled(bufnr, type, is_test_file) or is_test_file
end

--- Adapter options.
setmetatable(M, {
  ---@param opts DartAdapterOptions
  __call = function(_, opts)
    M.options = opts

    return M
  end,
})

return M
