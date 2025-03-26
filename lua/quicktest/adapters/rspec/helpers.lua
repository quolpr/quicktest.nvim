local fs = require("quicktest.fs_utils")

local function build_file_args(args, params)
  local f = params.file

  if params.line_no then
    f = f .. ":" .. params.line_no
  end

  table.insert(args, f)
end

---@param bufnr integer
---@return string | nil
local function find_cwd(bufnr)
  local fname = vim.api.nvim_buf_get_name(bufnr)

  return fs.find_ancestor_of_file(fname, "Gemfile")
end

---@param bufnr integer
---@return string
local function get_cwd(bufnr, options)
  local fallback = find_cwd(bufnr) or vim.fn.getcwd()

  return options.cwd and options.cwd(bufnr, fallback) or fallback
end

-- https://rspec.info/documentation/3.5/rspec-core/RSpec/Core/Configuration.html
---@param cwd string
---@return boolean
local function is_rspec_project(cwd)
  for _, file in ipairs({ ".rspec", ".rspec-local" }) do
    local path = fs.path.join(cwd, file)
    if fs.path.exists(path) then
      return true
    end
  end

  return false
end

---@param bufname string
---@return boolean
local function is_ruby_test_file(bufname)
  for _, suffix in ipairs({ "_spec.rb", "_test.rb" }) do
    if vim.endswith(bufname, suffix) then
      return true
    end
  end

  return false
end

local M = {}

---@param params RspecRunParams
---@return string[]
function M.build_command_args(params)
  local args = {}

  if params.dir then
    table.insert(args, params.dir)
  elseif params.file then
    build_file_args(args, params)
  end

  return args
end

---@param bufnr integer
---@param options RspecAdapterOptions
---@return string
M.get_bin = function(bufnr, options)
  local fallback = "rspec"

  return options.bin and options.bin(bufnr, fallback) or fallback
end

---@param bufnr integer
---@param options RspecAdapterOptions
---@return boolean
M.is_enabled = function(bufnr, options)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local cwd = get_cwd(bufnr, options)

  return is_ruby_test_file(bufname) and is_rspec_project(cwd)
end

return M
