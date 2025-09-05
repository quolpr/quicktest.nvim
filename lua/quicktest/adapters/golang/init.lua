local ts = require("quicktest.adapters.golang.ts")
local cmd = require("quicktest.adapters.golang.cmd")
local fs = require("quicktest.fs_utils")
local Job = require("plenary.job")

---@class GoAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field additional_args (fun(bufnr: integer): string[])?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?
---@field dap (fun(bufnr: integer, params: GoRunParams): table)?

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
---@field opts AdapterRunOpts

---@param bufnr integer
---@return string
M.get_cwd = function(bufnr)
  local current = find_cwd(bufnr) or vim.fn.getcwd()

  return M.options.cwd and M.options.cwd(bufnr, current) or current
end

M.get_bin = function(bufnr)
  local current = "go"

  return M.options.bin and M.options.bin(bufnr, current) or current
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return GoRunParams | nil, string | nil
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  local module = get_module_path(cwd, bufnr) or "."

  local func_names = ts.get_func_names(bufnr)
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
    opts = opts,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return GoRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local func_names = ts.get_nearest_func_names(bufnr, cursor_pos)
  local sub_name = ts.get_sub_testcase_name(bufnr, cursor_pos)
  --- @type string[]
  local sub_func_names = {}
  if sub_name then
    sub_func_names = { sub_name }
  end
  local cwd = M.get_cwd(bufnr)
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
    opts = opts,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return GoRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  local module = "./..."

  return {
    func_names = {},
    sub_func_names = {},
    cwd = cwd,
    module = module,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return GoRunParams | nil, string | nil
M.build_dir_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  local module = get_module_path(cwd, bufnr) or "."

  return {
    func_names = {},
    sub_func_names = {},
    cwd = cwd,
    module = module,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  },
    nil
end

---@param params GoRunParams
---@param send fun(data: CmdData)
---@return integer
M.run = function(params, send)
  local additional_args = M.options.additional_args and M.options.additional_args(params.bufnr) or {}
  additional_args = params.opts.additional_args and vim.list_extend(additional_args, params.opts.additional_args)
    or additional_args

  local args = cmd.build_args(params.module, params.func_names, params.sub_func_names, additional_args)
  args = M.options.args and M.options.args(params.bufnr, args) or args

  local bin = M.get_bin(params.bufnr)
  bin = M.options.bin and M.options.bin(params.bufnr, bin) or bin

  local env = vim.fn.environ()
  env = M.options.env and M.options.env(params.bufnr, env) or env

  local current_out = ""
  local job = Job:new({
    command = bin,
    args = args,
    env = env,
    cwd = params.cwd,
    on_stdout = function(_, data)
      --- @type boolean, GoLogEntry
      local status, res = pcall(vim.json.decode, data)

      if not status then
        send({ type = "stdout", raw = data, output = data })

        return
      end

      if res.Output and res.Output ~= "" then
        current_out = current_out .. res.Output --[[@as string]]
      end

      if string.find(current_out, "\n") then
        local out = current_out:gsub("\n", "")

        current_out = ""
        send({ type = "stdout", raw = data, decoded = res, output = out })
      end
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
  local additional_args = M.options.additional_args and M.options.additional_args(params.bufnr) or {}
  additional_args = params.opts.additional_args and vim.list_extend(additional_args, params.opts.additional_args)
    or additional_args

  local args = cmd.build_args(params.module, params.func_names, params.sub_func_names, additional_args)
  args = M.options.args and M.options.args(params.bufnr, args) or args

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

      if not decoded then
        return
      end

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
  local is_test_file = false
  if type == "line" or type == "file" then
    is_test_file = vim.endswith(bufname, "_test.go")
  else
    is_test_file = vim.endswith(bufname, ".go")
  end

  if M.options.is_enabled == nil then
    return is_test_file
  end

  return M.options.is_enabled(bufnr, type, is_test_file)
end

---@param bufnr integer
---@param params GoRunParams
---@return table
M.build_dap_config = function(bufnr, params)
  local additional_args = M.options.additional_args and M.options.additional_args(bufnr) or {}
  additional_args = params.opts.additional_args and vim.list_extend(additional_args, params.opts.additional_args)
    or additional_args

  local test_args = cmd.build_dap_args(params.func_names, params.sub_func_names, additional_args)

  local env = vim.fn.environ()
  env = M.options.env and M.options.env(bufnr, env) or env

  local config = {
    type = "go",
    name = "Debug Test",
    request = "launch",
    mode = "test",
    program = params.module == "./..." and "." or params.module,
    args = test_args,
    env = env,
    cwd = params.cwd,
  }

  if M.options.dap then
    config = vim.tbl_extend("force", config, M.options.dap(bufnr, params))
  end

  return config
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
