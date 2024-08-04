local M = {}

-- Function to get the file type of a given buffer number
local function get_buffer_file_type(buffer_number)
  -- Use pcall to handle any errors gracefully
  local status, filetype = pcall(vim.api.nvim_buf_get_option, buffer_number, "filetype")
  if status then
    return filetype
  else
    -- If there's an error (e.g., invalid buffer number), return a default value or error message
    return "Error retrieving file type: " .. filetype
  end
end

---@param bufnr integer
---@return TSNode?
local function get_root_node(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, get_buffer_file_type(bufnr))
  if not parser then
    return
  end

  local tree = parser:parse()[1]
  if not tree then
    return
  end

  return tree:root()
end

--- Test the given Treesitter expression against the given buffer.
--- Return `true` if the expr matches.
---@param expr string
---@param bufnr integer
---@return boolean 
function M.matches(expr, bufnr)
  local root = get_root_node(bufnr)
  if not root then
    return false
  end

  local query = vim.treesitter.query.parse(get_buffer_file_type(bufnr), expr)
  for x in query:iter_matches(root, bufnr) do
    return true
  end
  return false
end

function M.get_current_test(expr, bufnr, cursor_pos, search_type)
  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local query = vim.treesitter.query.parse(get_buffer_file_type(bufnr), expr)

  local is_inside_test = false
  local curr_row, _ = unpack(cursor_pos)

  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]

    if name == search_type .. ".definition" then
      local start_row, _, end_row, _ = node:range()

      is_inside_test = curr_row > start_row and curr_row <= end_row + 1
    elseif name == search_type .. ".name" and is_inside_test then
      return node
    end
  end
end

function M.get_current_test_range(expr, bufnr, cursor_pos, search_type)
  local node = M.get_current_test(expr, bufnr, cursor_pos, search_type)

  if not node then
    return
  end

  return { node:range() }
end

function M.get_current_test_name(expr, bufnr, cursor_pos, search_type)
  local node = M.get_current_test(expr, bufnr, cursor_pos, search_type)

  if not node then
    return
  end

  return vim.treesitter.get_node_text(node, bufnr)
end

return M
