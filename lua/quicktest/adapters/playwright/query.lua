return [[
    ; -- Namespaces --
    ; Matches: `describe('context')`
    ((call_expression
      function: (identifier) @func_name (#eq? @func_name "describe")
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; Matches: `describe.only('context')`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#eq? @func_name "describe")
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition

    ; -- Tests --
    ; Matches: `test('test')`
    ((call_expression
      function: (identifier) @func_name (#eq? @func_name "test")
      arguments: (arguments (string (string_fragment) @test.name) (arrow_function))
    )) @test.definition
    ; Matches: `test.only('test')`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#eq? @func_name "test")
      )
      arguments: (arguments (string (string_fragment) @test.name) (arrow_function))
    )) @test.definition
]]
