local Job = require("plenary.job")
local q = require("quicktest.adapters.pytest.query")
local ts = require("quicktest.ts")
local fs = require("quicktest.fs_utils")

---@class PytestAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?

local M = {
  name = "pytest",
  ---@type PytestAdapterOptions
  options = {},
}

---@class PytestRunParams
---@field bufnr integer
---@field file string?
---@field ns_name string
---@field test_name string
---@field cwd string
---@field bin string
---@field opts AdapterRunOpts

---@param bufnr integer
---@return string?
M.get_cwd = function(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file
  local detected_cwd = fs.find_ancestor_of_file(path, "pyproject.toml") or path

  return M.options.cwd and M.options.cwd(bufnr, detected_cwd) or detected_cwd
end

---@param bufnr integer
---@return string?
M.get_bin = function(cwd, bufnr)
  return M.options.bin and M.options.bin(bufnr, "pytest") or "pytest"
end

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return PytestRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(cwd, bufnr)

  if not bin then
    return nil, "Failed to find pytest binary"
  end

  local file = vim.api.nvim_buf_get_name(bufnr)

  local params = {
    bufnr = bufnr,
    test_name = ts.get_current_test_name(q, bufnr, cursor_pos, "test"),
    file = file,
    cwd = cwd,
    bin = bin,
    opts = opts,
    -- Add other parameters as needed
  }
  return params, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return PytestRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(cwd, bufnr)

  if not bin then
    return nil, "Failed to find pytest binary"
  end

  local params = {
    bufnr = bufnr,
    cwd = cwd,
    bin = bin,
    opts = opts,
    -- Add other parameters as needed
  }
  return params, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return PytestRunParams | nil, string | nil
---@diagnostic disable-next-line: unused-local
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  if not cwd then
    return nil, "Failed to find cwd"
  end

  local bin = M.get_bin(cwd, bufnr)

  if not bin then
    return nil, "Failed to find pytest binary"
  end

  local file = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path

  local params = {
    bufnr = bufnr,
    cwd = cwd,
    bin = bin,
    file = file,
    opts = opts,
    -- Add other parameters as needed
  }

  return params, nil
end

---@param params PytestRunParams
local function build_args(params)
  local args = {}

  if params.test_name ~= "" and params.test_name ~= nil then
    vim.list_extend(args, {
      "-k",
      params.test_name,
    })
  end

  if params.file ~= "" and params.file ~= nil then
    vim.list_extend(args, {
      params.file,
    })
  end

  return args
end

--- Executes the test with the given parameters.
---@param params PytestRunParams
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

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@param type RunType
---@return boolean
M.is_enabled = function(bufnr, type)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  is_test_file = string.match(file_path, "test_.*%.py$")

  if M.options.is_enabled == nil then
    return is_test_file
  end

  return M.options.is_enabled(bufnr, type, is_test_file)
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
