local Job = require("plenary.job")
local ts = require("quicktest.ts")

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
    -- Define a pattern to match '$' followed by a character (not escaped)
    local pattern = "(\\?%$)(%a)"

    -- Replace occurrences of '$' followed by a character with just the character
    local result = str:gsub(pattern, function(dollar, char)
      -- If the '$' is escaped, leave it as is
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
}
---@class DartRunParams
---@field func_name? string
---@field bufnr integer
---@field cursor_pos integer[]
---@field path string
---@field cwd string

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_line_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local pwd = find_project_directory(filepath)
  if pwd == nil then
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
    cwd = pwd,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_file_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local pwd = find_project_directory(filepath)
  if pwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    path = filepath,
    cwd = pwd,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_dir_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local pwd = find_project_directory(filepath)
  if pwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end
  local folder = vim.fn.fnamemodify(filepath, ":h")
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    path = folder,
    cwd = pwd,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return DartRunParams | nil, nil | string
M.build_all_run_params = function(bufnr, cursor_pos)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local pwd = find_project_directory(filepath)
  if pwd == nil then
    return nil, "Unable to locate project directory, could not find pubspec.yaml"
  end
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    path = "",
    cwd = pwd,
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

  local job = Job:new({
    command = "flutter",
    args = args,
    cwd = params.cwd,
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
---@return boolean
M.is_enabled = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return vim.endswith(bufname, "_test.dart") or vim.endswith(bufname, ".dart")
end

return M
