local Job = require("plenary.job")

local diagnostics = require("quicktest.adapters.rspec.diagnostics")
local helpers = require("quicktest.adapters.rspec.helpers")

---@class RspecAdapterOptions
---@field bin (fun(bufnr: integer, fallback: string): string)?
---@field cwd (fun(bufnr: integer, fallback: string): string)?
---@field is_enabled (fun(bufnr: integer, fallback: boolean): boolean)?

---@class RspecRunParams
---@field bufnr integer
---@field dir string?
---@field file string?
---@field line_no integer?

---@alias RspecBuildFunc fun(bufnr: integer, cursor_pos: integer[], options: RspecAdapterOptions): RspecRunParams, string | nil
---@alias RspecResultType { type: string, output: string }

local M = {
  name = "rspec",
  options = {},
}

local diagnostics_ns = vim.api.nvim_create_namespace("quicktest-rspec")

---@type RspecBuildFunc
M.build_line_run_params = function(bufnr, cursor_pos)
  return {
    bufnr = bufnr,
    file = vim.api.nvim_buf_get_name(bufnr),
    line_no = cursor_pos[1],
  }, nil
end

---@type RspecBuildFunc
M.build_file_run_params = function(bufnr)
  return {
    bufnr = bufnr,
    file = vim.api.nvim_buf_get_name(bufnr),
  }, nil
end

---@type RspecBuildFunc
M.build_dir_run_params = function(bufnr)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local dir = vim.fn.fnamemodify(fname, ":h")

  return {
    bufnr = bufnr,
    dir = dir,
  }, nil
end

---@type RspecBuildFunc
M.build_all_run_params = function(bufnr)
  return { bufnr = bufnr }, nil
end

---@param params RspecRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  diagnostics.clear(diagnostics_ns)

  ---@diagnostic disable-next-line: missing-fields
  local job = Job:new({
    command = helpers.get_bin(params.bufnr, M.options),
    args = helpers.build_command_args(params),
    on_stdout = function(_, data)
      send({ type = "stdout", output = data })
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()

  ---@diagnostic disable-next-line: return-type-mismatch
  return job.pid
end

---@param params RspecRunParams
---@return string
M.title = function(params)
  local args = helpers.build_command_args(params)
  local msg = table.concat(args, " ")

  return "Running tests... " .. msg
end

---@param results RspecResultType
M.after_run = function(_, results)
  diagnostics.set(diagnostics_ns, results)
end

---@type RspecBuildFunc
---@return boolean
M.is_enabled = function(bufnr)
  local fallback = helpers.is_enabled(bufnr, M.options)
  local option = M.options.is_enabled and M.options.is_enabled(bufnr, fallback)
  if option ~= nil then
    return option
  end

  return fallback
end

setmetatable(M, {
  ---@param opts RspecAdapterOptions
  __call = function(_, opts)
    M.options = opts

    return M
  end,
})

return M
