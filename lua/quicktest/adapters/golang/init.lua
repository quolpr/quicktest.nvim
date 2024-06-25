local ts = require("quicktest.adapters.golang.ts")
local cmd = require("quicktest.adapters.golang.cmd")
local fs = require("quicktest.fs_utils")
local Job = require("plenary.job")

---@class GoAdapterOptions
---@field cwd (fun(bufnr: integer): string)?
---@field bin (fun(bufnr: integer): string)?
---@field additional_args (fun(bufnr: integer): string[])?

local M = {
  name = "go",
  ---@type GoAdapterOptions
  options = {},
}

local ns = vim.api.nvim_create_namespace("quicktest-go")

--- @param bufnr integer
--- @return string | nil
local function find_cwd(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file

  return fs.find_ancestor_of_file(path, "go.mod")
end

---@param cwd string
---@param bufnr integer
---@return string | nil
local function get_module_path(cwd, bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  -- Normalize the paths to remove trailing slashes for consistency
  cwd = string.gsub(cwd, "/$", "")
  file_path = string.gsub(file_path, "/$", "")

  -- Check if the file_path starts with the cwd and extract the relative part
  if string.sub(file_path, 1, #cwd) == cwd then
    local relative_path = string.sub(file_path, #cwd + 2) -- +2 to remove the leading slash
    local module_path = "./" .. vim.fn.fnamemodify(relative_path, ":h") -- Get directory path without filename
    return module_path
  else
    return nil -- Return nil if the file_path is not under cwd
  end
end

---@class GoLogEntry
---@field Action '"start"' | '"run"' | '"pause"' | '"cont"' | '"pass"' | '"bench"' | '"fail"' | '"output"' | '"skip"'
---@field Package string
---@field Time string
---@field Test? string
---@field Output? string
---@field Elapsed? number

---@class GoRunParams
---@field func_names string[]
---@field sub_func_names string[]
---@field cwd string
---@field module string
---@field bufnr integer
---@field cursor_pos integer[]

---@param bufnr integer
---@param cursor_pos integer[]
---@return GoRunParams | nil, string | nil
M.build_file_run_params = function(bufnr, cursor_pos)
  local func_names = ts.get_func_names(bufnr)
  local cwd = M.options.cwd and M.options.cwd(bufnr) or find_cwd(bufnr) or vim.fn.getcwd()
  local module = get_module_path(cwd, bufnr) or "."

  if not func_names or #func_names == 0 then
    return nil, "No tests to run"
  end

  return {
    func_names = func_names,
    sub_func_names = {},
    cwd = cwd,
    module = module,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return GoRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos)
  local func_names = ts.get_nearest_func_names(bufnr, cursor_pos)
  local sub_name = ts.get_sub_testcase_name(bufnr, cursor_pos)
  --- @type string[]
  local sub_func_names = {}
  if sub_name then
    sub_func_names = { sub_name }
  end
  local cwd = M.options.cwd and M.options.cwd(bufnr) or find_cwd(bufnr) or vim.fn.getcwd()
  local module = get_module_path(cwd, bufnr) or "."

  if not func_names or #func_names == 0 then
    return nil, "No tests to run"
  end

  return {
    func_names = func_names,
    sub_func_names = sub_func_names,
    cwd = cwd,
    module = module,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return GoRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos)
  local cwd = M.options.cwd and M.options.cwd(bufnr) or find_cwd(bufnr) or vim.fn.getcwd()
  local module = "./..."

  return {
    func_names = {},
    sub_func_names = {},
    cwd = cwd,
    module = module,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return GoRunParams | nil, string | nil
M.build_dir_run_params = function(bufnr, cursor_pos)
  local cwd = M.options.cwd and M.options.cwd(bufnr) or find_cwd(bufnr) or vim.fn.getcwd()
  local module = get_module_path(cwd, bufnr) or "."

  return {
    func_names = {},
    sub_func_names = {},
    cwd = cwd,
    module = module,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  },
    nil
end

---@param params GoRunParams
---@param send fun(data: CmdData)
---@return integer
M.run = function(params, send)
  local args = cmd.build_args(
    params.module,
    params.func_names,
    params.sub_func_names,
    M.options.additional_args and M.options.additional_args(params.bufnr) or {}
  )

  local job = Job:new({
    command = M.options.bin and M.options.bin(params.bufnr) or "go",
    args = args,
    cwd = params.cwd,
    on_stdout = function(_, data)
      --- @type GoLogEntry
      local res = vim.json.decode(data)

      if res.Output and res.Output ~= "" then
        res.Output = res.Output:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
      end

      send({ type = "stdout", raw = data, decoded = res, output = res.Output })
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", raw = data, output = data })
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

M.title = function(params)
  local args = cmd.build_args(
    params.module,
    params.func_names,
    params.sub_func_names,
    M.options.additional_args and M.options.additional_args(params.bufnr) or {}
  )

  return "Running test: " .. table.concat({ unpack(args, 2) }, " ")
end

---@param params GoRunParams
---@param results CmdData[]
M.after_run = function(params, results)
  local diagnostics = {}

  for _, result in ipairs(results) do
    if result.type == "stdout" then
      --- @type GoLogEntry
      local decoded = result.decoded

      if decoded.Action == "fail" then
        local line_no = ts.get_func_def_line_no(params.bufnr, decoded.Test)

        if line_no then
          table.insert(diagnostics, {
            lnum = line_no,
            col = 0,
            severity = vim.diagnostic.severity.ERROR,
            message = "FAILED",
            source = "Test",
            user_data = "test",
          })
        end
      end
    end
  end

  vim.diagnostic.set(ns, params.bufnr, diagnostics, {})
end

---@param bufnr integer
---@param type RunType
---@return boolean
M.is_enabled = function(bufnr, type)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if type == "line" or type == "file" then
    return vim.endswith(bufname, "_test.go")
  else
    return vim.endswith(bufname, ".go")
  end
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
