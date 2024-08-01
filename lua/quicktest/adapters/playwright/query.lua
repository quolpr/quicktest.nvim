return [[
    ; -- Namespaces --
    ; Matches: `test.describe('context')`
    ((call_expression
       function: (member_expression
         object: (identifier) @obj_name (#eq? @obj_name "test")  
         property: (property_identifier) @prop_ident (#eq? @prop_ident "describe")
       )
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; -- Tests --
    ; Matches: `test('test')`
    ((call_expression
      function: (identifier) @func_name (#eq? @func_name "test")
      arguments: (arguments (string (string_fragment) @test.name) (arrow_function))
    )) @test.definition
]]
