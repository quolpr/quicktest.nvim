---@return table<string, number> keys: file paths relative to cwd
local function key_bufnrs_by_path()
  local ret = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local fname = vim.api.nvim_buf_get_name(buf)
      local rel_path = vim.fn.fnamemodify(fname, ":.")
      ret[rel_path] = buf
    end
  end

  return ret
end

---@param line_no integer
---@return vim.Diagnostic
local function new_diagnostic(line_no)
  return {
    lnum = tonumber(line_no) - 1,
    col = 0,
    severity = vim.diagnostic.severity.ERROR,
    message = "FAILED",
    source = "Test",
    user_data = "test",
  }
end

local output_re = "rspec%s+(.+):(%d+)"

---@param results RspecResultType
---@return table<string, vim.Diagnostic[]> keys: file paths relative to cwd
local function key_diagnostics_by_path(results)
  local ret = {}

  for _, result in ipairs(results) do
    if result.type == "stdout" and result.output then
      local path, line_no = string.match(result.output, output_re)

      if path and line_no then
        local rel_path = vim.fn.fnamemodify(path, ":.")
        ret[rel_path] = ret[rel_path] or {}
        table.insert(ret[rel_path], new_diagnostic(line_no))
      end
    end
  end

  return ret
end

local M = {}

-- Clear diagnostics on all open buffers.
---@param diagnostics_ns integer
M.clear = function(diagnostics_ns)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.diagnostic.set(diagnostics_ns, buf, {}, {})
    end
  end
end

-- Set diagnostics on all open buffers matching test failure files.
---@param diagnostics_ns integer
---@param results RspecResultType
M.set = function(diagnostics_ns, results)
  local path_buffers = key_bufnrs_by_path()
  local path_diagnostics = key_diagnostics_by_path(results)

  for path, diagnostics in pairs(path_diagnostics) do
    if path_buffers[path] then
      vim.diagnostic.set(diagnostics_ns, path_buffers[path], diagnostics, {})
    end
  end
end

return M
