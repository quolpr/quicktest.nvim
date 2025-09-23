-- Adapted from https://github.com/marilari88/neotest-vitest/blob/main/lua/neotest-vitest/util.lua
local validate = vim.validate
local uv = vim.loop

local M = {}

-- Some path utilities
M.path = (function()
  local is_windows = uv.os_uname().version:match("Windows")
  local path_separator = (function()
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

  local function sanitize(path)
    if is_windows then
      path = path:sub(1, 1):upper() .. path:sub(2)
      path = path:gsub("\\", "/")
    end
    return path
  end

  ---@return string|false
  local function exists(filename)
    local stat = uv.fs_stat(filename)
    return stat and stat.type or false
  end

  local function is_dir(filename)
    return exists(filename) == "directory"
  end

  local function is_file(filename)
    return exists(filename) == "file"
  end

  local function is_fs_root(path)
    if is_windows then
      return path:match("^%a:$")
    else
      return path == "/"
    end
  end

  local function is_absolute(filename)
    if is_windows then
      return filename:match("^%a:") or filename:match("^\\\\")
    else
      return filename:match("^/")
    end
  end

  local function dirname(path)
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

  local function path_join(...)
    return table.concat(vim.fn.flatten({ ... }), path_separator)
  end

  -- Traverse the path calling cb along the way.
  local function traverse_parents(path, cb)
    path = uv.fs_realpath(path)
    local dir = path
    -- Just in case our algo is buggy, don't infinite loop.
    for _ = 1, 100 do
      dir = dirname(dir)
      if not dir then
        return
      end
      -- If we can't ascend further, then stop looking.
      if cb(dir, path) then
        return dir, path
      end
      if is_fs_root(dir) then
        break
      end
    end
  end

  -- Iterate the path until we find the rootdir.
  local function iterate_parents(path)
    local function it(_, v)
      if v and not is_fs_root(v) then
        v = dirname(v)
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

  local function is_descendant(root, path)
    if not path then
      return false
    end

    local function cb(dir, _)
      return dir == root
    end

    local dir, _ = traverse_parents(path, cb)

    return dir == root
  end

  return {
    is_dir = is_dir,
    is_file = is_file,
    is_absolute = is_absolute,
    exists = exists,
    dirname = dirname,
    join = path_join,
    sanitize = sanitize,
    traverse_parents = traverse_parents,
    iterate_parents = iterate_parents,
    is_descendant = is_descendant,
    path_separator = path_separator,
  }
end)()

--- @param start_path string
--- @param func fun(path: string): boolean
--- @return string?
function M.find_ancestor(start_path, func)
  validate({ func = { func, "f" } })
  if func(start_path) then
    return start_path
  end
  local guard = 100
  for path in M.path.iterate_parents(start_path) do
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

--- @param start_path string
--- @param dir string
--- @return string?
function M.find_ancestor_of_dir(start_path, dir)
  return M.find_ancestor(start_path, function(path)
    if M.path.is_dir(M.path.join(path, dir)) then
      return true
    end

    return false
  end)
end

--- @param start_path string
--- @param file string
--- @return string?
function M.find_ancestor_of_file(start_path, file)
  return M.find_ancestor(start_path, function(path)
    if M.path.is_file(M.path.join(path, file)) then
      return true
    end

    return false
  end)
end

function M.root_pattern(...)
  local patterns = vim.fn.flatten({ ... })
  local function matcher(path)
    for _, pattern in ipairs(patterns) do
      for _, p in ipairs(vim.fn.glob(M.path.join(path, pattern), true, true)) do
        if M.path.exists(p) then
          return path
        end
      end
    end
  end

  return function(start_path)
    return M.find_ancestor(start_path, matcher)
  end
end

-- Function to extract the filename from a full path based on the base path
function M.extract_filename(base_path, full_path)
  -- Ensure the cwd ends with a slash to avoid partial matches
  if string.sub(base_path, -1) ~= "/" then
    base_path = base_path .. "/"
  end

  -- Check if the full path starts with the cwd
  local start_pos = string.find(full_path, base_path, 1, true)
  if start_pos then
    -- Remove the cwd part, including any leading slash from the remaining path
    local filename = string.sub(full_path, #base_path + 1)
    return filename
  else
    -- Return the full path if it does not start with cwd
    return full_path
  end
end

return M
