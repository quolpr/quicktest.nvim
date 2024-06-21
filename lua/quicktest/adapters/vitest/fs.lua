-- Adapted from https://github.com/marilari88/neotest-vitest/blob/main/lua/neotest-vitest/util.lua
--
local M = {}

local uv = vim.loop

local is_windows = uv.os_uname().version:match("Windows")

M.path_sep = (function()
  if jit then
    local os = string.lower(jit.os)
    if os == "linux" or os == "osx" or os == "bsd" then
      return "/"
    else
      return "\\"
    end
  else
    return package.config:sub(1, 1)
  end
end)()

function M.is_fs_root(path)
  if is_windows then
    return path:match("^%a:$")
  else
    return path == "/"
  end
end

function M.dirname(path)
  local strip_dir_pat = "/([^/]+)$"
  local strip_sep_pat = "/$"
  if not path or #path == 0 then
    return
  end
  local result = path:gsub(strip_sep_pat, ""):gsub(strip_dir_pat, "")
  if #result == 0 then
    if is_windows then
      return path:sub(1, 2):upper()
    else
      return "/"
    end
  end
  return result
end

function M.iterate_parents(path)
  local function it(_, v)
    if v and not M.is_fs_root(v) then
      v = M.dirname(v)
    else
      return
    end
    if v and uv.fs_realpath(v) then
      return v, path
    else
      return
    end
  end
  return it, path, path
end

function M.path_join(...)
  return table.concat(vim.tbl_flatten({ ... }), "/")
end

function M.exists(filename)
  local stat = uv.fs_stat(filename)
  return stat and stat.type or false
end

function M.search_ancestors(start_path, func)
  vim.validate({ func = { func, "f" } })
  if func(start_path) then
    return start_path
  end
  local guard = 100
  for path in M.iterate_parents(start_path) do
    -- Prevent infinite recursion if our algorithm breaks
    guard = guard - 1
    if guard == 0 then
      return
    end

    if func(path) then
      return path
    end
  end
end

function M.root_pattern(...)
  local patterns = vim.tbl_flatten({ ... })

  local function matcher(path)
    for _, pattern in ipairs(patterns) do
      for _, p in ipairs(vim.fn.glob(M.path_join(path, pattern), true, true)) do
        if M.exists(p) then
          return path
        end
      end
    end
  end
  return function(start_path)
    return M.search_ancestors(start_path, matcher)
  end
end

--- @param bufnr integer
--- @param by string
--- @return string | nil
function M.find_cwd(bufnr, by)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file

  while path and #path > 1 do
    local go_mod_path = path .. M.path_sep .. by
    if vim.fn.filereadable(go_mod_path) == 1 then
      return path
    end
    path = vim.fn.fnamemodify(path, ":h") -- Move up one directory level
  end

  return nil -- Return nil if 'go.mod' is not found in any parent directory
end

return M
