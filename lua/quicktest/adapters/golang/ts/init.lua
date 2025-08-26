-- taken from https://github.com/yanskun/gotests.nvim

local M = {

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

  table_tests_list = [[
    ;; query for list table tests
    (block
      (short_var_declaration
        left: (expression_list
          (identifier) @test.cases
        )
        right: (expression_list
          (composite_literal
            (literal_value
              (literal_element
                (literal_value
                  (keyed_element
                    (literal_element
                      (identifier) @test.field.name
                    )
                    (literal_element
                      (interpreted_string_literal) @test.name
                    )
                  )
                )
              ) @test.definition
            )
          )
        )
      )
      (for_statement
        (range_clause
          left: (expression_list
            (identifier) @test.case
          )
          right: (identifier) @test.cases1 (#eq? @test.cases @test.cases1)
        )
        body: (block
          (expression_statement
            (call_expression
              function: (selector_expression
                operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
                field: (field_identifier) @test.method (#match? @test.method "^Run$")
              )
              arguments: (argument_list
                (selector_expression
                  operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                  field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
                )
              )
            )
          )
        )
      )
    )
  ]],

  table_tests_loop = [[
    ;; query for list table tests (wrapped in loop)
    (for_statement
      (range_clause
        left: (expression_list
          (identifier)
          (identifier) @test.case
        )
        right: (composite_literal
          type: (slice_type
            element: (struct_type
              (field_declaration_list
                (field_declaration
                  name: (field_identifier)
                  type: (type_identifier)
                )
              )
            )
          )
          body: (literal_value
            (literal_element
              (literal_value
                (keyed_element
                  (literal_element
                    (identifier)
                  )  @test.field.name
                  (literal_element
                    (interpreted_string_literal) @test.name
                  )
                )
              ) @test.definition
            )
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier)
              field: (field_identifier)
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier)
                field: (field_identifier) @test.field.name1
              ) (#eq? @test.field.name @test.field.name1)
            )
          )
        )
      )
    )
  ]],

  table_tests_unkeyed = [[
    ;; query for table tests with unkeyed struct literals
    (block
      (short_var_declaration
        left: (expression_list 
          (identifier) @test.cases
        )
        right: (expression_list
          (composite_literal
            type: (slice_type
              element: (struct_type
                (field_declaration_list
                  (field_declaration
                    name: (field_identifier) @test.field.name
                    type: (type_identifier)
                  )
                )
              )
            )
            body: (literal_value
              (literal_element
                (literal_value
                  (literal_element
                    (interpreted_string_literal) @test.name
                  )
                ) @test.definition @test.name
              )
            )
          )
        )
      )
      (for_statement
        (range_clause
          left: (expression_list
            (identifier) @test.index
            (identifier) @test.case
          )
          right: (identifier) @test.cases1 (#eq? @test.cases @test.cases1)
        )
        body: (block
          (expression_statement
            (call_expression
              function: (selector_expression
                operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
                field: (field_identifier) @test.method (#match? @test.method "^Run$")
              )
              arguments: (argument_list
                (selector_expression
                  operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                  field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
                )
              )
            )
          )
        )
      )
    )
  ]],

  table_tests_loop_unkeyed = [[
    ;; query for table tests with inline structs (not keyed, wrapped in loop)
    (for_statement
      (range_clause
        left: (expression_list
          (identifier)
          (identifier) @test.case
        )
        right: (composite_literal
          type: (slice_type
            element: (struct_type
              (field_declaration_list
                (field_declaration
                  name: (field_identifier) @test.field.name
                  type: (type_identifier) @field.type (#eq? @field.type "string")
                )
              )
            )
          )
          body: (literal_value
            (literal_element
              (literal_value
                (literal_element
                  (interpreted_string_literal) @test.name
                )
                (literal_element)
              ) @test.definition @test.name
            )
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
              )
            )
          )
        )
      )
    )
  ]],

  table_tests_inline = [[
    ;; query for inline table tests (range over slice literal)
    (for_statement
      (range_clause
        left: (expression_list
          (identifier)
          (identifier) @test.case
        )
        right: (composite_literal
          type: (slice_type
            element: (type_identifier)
          )
          body: (literal_value
            (literal_element
              (literal_value
                (keyed_element
                  (literal_element
                    (identifier) @test.field.name
                  )
                  (literal_element
                    (interpreted_string_literal) @test.name
                  )
                )
              ) @test.definition
            )
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
              )
            )
          )
        )
      )
    )
  ]],

  -- Map-based table tests where test name is the map key
  table_tests_map_key = [[
    ;; query for map-based table tests with string keys
    (for_statement
      (range_clause
        left: (expression_list
          (identifier) @test.key.name
          (identifier) @test.case
        )
        right: (composite_literal
          type: (map_type
            key: (type_identifier) @map.key.type
            value: (type_identifier)
          ) (#eq? @map.key.type "string")
          body: (literal_value
            (keyed_element
              (literal_element
                (interpreted_string_literal) @test.name
              )
              (literal_element
                (literal_value) @test.definition
              )
            ) @test.definition
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (identifier) @test.key.name1 (#eq? @test.key.name @test.key.name1)
            )
          )
        )
      )
    )
  ]],

  -- Map-based table tests where test name is a struct field (like tt.name)
  table_tests_map_field = [[
    ;; query for map-based table tests using struct field as test name
    (for_statement
      (range_clause
        left: (expression_list
          (identifier) @test.key.name
          (identifier) @test.case
        )
        right: (composite_literal
          type: (map_type
            key: (type_identifier) @map.key.type
            value: (type_identifier)
          ) (#eq? @map.key.type "string")
          body: (literal_value
            (keyed_element
              (literal_element
                (interpreted_string_literal) @test.map.key
              )
              (literal_element
                (literal_value
                  (keyed_element
                    (literal_element
                      (identifier) @test.field.name
                    )
                    (literal_element
                      (interpreted_string_literal) @test.name
                    )
                  )
                ) @test.definition
              )
            ) @test.definition
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
              )
            )
          )
        )
      )
    )
  ]],
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

---@param bufnr integer
---@param cursor_pos integer[]
---@return string?
function M.get_table_test_name(bufnr, cursor_pos)
  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local all_queries = M.table_tests_list
    .. M.table_tests_loop
    .. M.table_tests_unkeyed
    .. M.table_tests_loop_unkeyed
    .. M.table_tests_inline
    .. M.table_tests_map_key
    .. M.table_tests_map_field
  local query = vim.treesitter.query.parse("go", all_queries)
  local curr_row, _ = unpack(cursor_pos)
  -- from 1-based to 0-based indexing
  curr_row = curr_row - 1

  -- Find test name at cursor position by checking test definitions
  local test_names = {}
  local test_definitions = {}
  
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()
    
    if name == "test.name" then
      table.insert(test_names, {
        text = vim.treesitter.get_node_text(node, bufnr),
        start_row = start_row,
        end_row = end_row,
        start_col = start_col,
        end_col = end_col
      })
    elseif name == "test.definition" then
      table.insert(test_definitions, {
        start_row = start_row,
        end_row = end_row,
        start_col = start_col,
        end_col = end_col
      })
    end
  end
  
  -- Find test definition that contains cursor, then find corresponding test name
  for _, def in ipairs(test_definitions) do
    if curr_row >= def.start_row and curr_row <= def.end_row then
      -- Find test name within this definition
      for _, name in ipairs(test_names) do
        if name.start_row >= def.start_row and name.end_row <= def.end_row then
          return name.text
        end
      end
    end
  end

  return nil
end

---Find the exact location of a sub-test within a parent test function
---@param bufnr integer
---@param parent_test_name string
---@param sub_test_name string
---@return integer? line number (0-based)
function M.find_sub_test_location(bufnr, parent_test_name, sub_test_name)
  local root = get_root_node(bufnr)
  if not root then
    return nil
  end

  -- First find the parent test function
  local parent_line = M.get_func_def_line_no(bufnr, parent_test_name)
  if not parent_line then
    return nil
  end

  -- Find the function node for the parent test
  local parent_func_node = nil
  local find_func_query = string.format(M.query_func_def_line_no, parent_test_name)
  local query = vim.treesitter.query.parse("go", find_func_query)
  
  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    -- Get the parent function_declaration node
    while node and node:type() ~= "function_declaration" do
      node = node:parent()
    end
    if node then
      parent_func_node = node
      break
    end
  end

  if not parent_func_node then
    return nil
  end

  -- Now search for t.Run calls within this function
  local sub_test_query = vim.treesitter.query.parse("go", M.query_sub_testcase_name)
  
  for id, node in sub_test_query:iter_captures(parent_func_node, bufnr, 0, -1) do
    local name = sub_test_query.captures[id]
    if name == "tc.name" then
      local test_name_text = vim.treesitter.get_node_text(node, bufnr)
      -- Remove quotes from the test name
      test_name_text = test_name_text:gsub('^"(.*)"$', '%1')
      
      if test_name_text == sub_test_name then
        local start_row, _, _, _ = node:start()
        return start_row
      end
    end
  end

  return nil
end

---Find the exact location of a table-driven test case within a parent test function
---@param bufnr integer
---@param parent_test_name string
---@param case_name string
---@return integer? line number (0-based)
function M.find_table_test_case_location(bufnr, parent_test_name, case_name)
  local root = get_root_node(bufnr)
  if not root then
    return nil
  end

  -- First find the parent test function
  local parent_line = M.get_func_def_line_no(bufnr, parent_test_name)
  if not parent_line then
    return nil
  end

  -- Find the function node for the parent test
  local parent_func_node = nil
  local find_func_query = string.format(M.query_func_def_line_no, parent_test_name)
  local query = vim.treesitter.query.parse("go", find_func_query)
  
  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    -- Get the parent function_declaration node
    while node and node:type() ~= "function_declaration" do
      node = node:parent()
    end
    if node then
      parent_func_node = node
      break
    end
  end

  if not parent_func_node then
    return nil
  end

  -- Search through all table test patterns within this function
  local all_queries = M.table_tests_list
    .. M.table_tests_loop
    .. M.table_tests_unkeyed
    .. M.table_tests_loop_unkeyed
    .. M.table_tests_inline
    .. M.table_tests_map_key
    .. M.table_tests_map_field

  local table_query = vim.treesitter.query.parse("go", all_queries)
  
  for id, node in table_query:iter_captures(parent_func_node, bufnr, 0, -1) do
    local name = table_query.captures[id]
    if name == "test.name" then
      local test_name_text = vim.treesitter.get_node_text(node, bufnr)
      -- Remove quotes from the test name and handle potential whitespace issues
      test_name_text = test_name_text:gsub('^"(.*)"$', '%1')
      test_name_text = test_name_text:gsub('^%s*(.-)%s*$', '%1') -- trim whitespace
      
      -- Match exactly, accounting for spaces and special characters
      -- Go converts spaces to underscores in test names, so normalize both for comparison
      local normalized_test_name = test_name_text:gsub(" ", "_")
      local normalized_case_name = case_name:gsub(" ", "_")
      
      if test_name_text == case_name or normalized_test_name == normalized_case_name then
        local start_row, _, _, _ = node:start()
        return start_row
      end
    end
  end
  
  return nil
end

return M
