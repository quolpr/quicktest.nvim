-- taken from https://github.com/yanskun/gotests.nvim

local M = {
  query_tbl_testcase_name = [[ ( literal_value (
      literal_element (
        literal_value .(
          keyed_element
            (literal_element (identifier))
            (literal_element (interpreted_string_literal) @test.name)
         )
       ) @test.block
    ))
  ]],

  query_func_name = [[(function_declaration name: (identifier) @func_name)]],

  query_func_def_line_no = [[(
    function_declaration name: (identifier) @func_name
    (#eq? @func_name "%s")
  )]],

  query_sub_testcase_name = [[ (call_expression
    (selector_expression
      (field_identifier) @method.name)
    (argument_list
      (interpreted_string_literal) @tc.name
      (func_literal) )
    (#eq? @method.name "Run")
  ) @tc.run ]],
}

---@param bufnr integer
---@return TSNode?
local function get_root_node(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, "go")
  if not parser then
    return
  end

  local tree = parser:parse()[1]
  if not tree then
    return
  end

  return tree:root()
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return string?
function M.get_current_func_name(bufnr, cursor_pos)
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = cursor_pos })
  if not node then
    return
  end

  while node do
    if node:type() == "function_declaration" then
      break
    end

    node = node:parent()
  end

  if not node then
    return
  end

  return vim.treesitter.get_node_text(node:child(1), bufnr)
end

---@param bufnr integer
---@return string[]
function M.get_func_names(bufnr)
  local root = get_root_node(bufnr)
  if not root then
    return {}
  end

  local query = vim.treesitter.query.parse("go", M.query_func_name)
  local out = {}

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "func_name" then
      table.insert(out, vim.treesitter.get_node_text(node, bufnr))
    end
  end

  return out
end

---@param bufnr number
---@param cursor_pos integer[]
---@return string[]
function M.get_nearest_func_names(bufnr, cursor_pos)
  local current_func_name = M.get_current_func_name(bufnr, cursor_pos)
  local func_names = { current_func_name }

  if not current_func_name then
    func_names = M.get_func_names(bufnr)
  end

  func_names = vim.tbl_filter(function(v)
    return vim.startswith(v, "Test")
  end, func_names)

  if #func_names == 0 then
    return {}
  end

  return func_names
end

---@param bufnr number
---@param name string
---@return integer?
function M.get_func_def_line_no(bufnr, name)
  local find_func_by_name_query = string.format(M.query_func_def_line_no, name)

  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local query = vim.treesitter.query.parse("go", find_func_by_name_query)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "func_name" then
      local row, _, _ = node:start()

      return row
    end
  end
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return string?
function M.get_sub_testcase_name(bufnr, cursor_pos)
  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local query = vim.treesitter.query.parse("go", M.query_sub_testcase_name)
  local is_inside_test = false
  local curr_row, _ = unpack(cursor_pos)

  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    -- tc_run is the first capture of a match, so we can use it to check if we are inside a test
    if name == "tc.run" then
      local start_row, _, end_row, _ = node:range()

      is_inside_test = curr_row >= start_row and curr_row <= end_row
    elseif name == "tc.name" and is_inside_test then
      return vim.treesitter.get_node_text(node, bufnr)
    end
  end

  return nil
end

return M
