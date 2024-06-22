local test_block_id_list = { "test", "feature", "property" }
for index, value in ipairs(test_block_id_list) do
  test_block_id_list[index] = '"' .. value .. '"'
end
local test_block_ids = table.concat(test_block_id_list, " ")

return [[
  ;; query
  ;; Describe blocks
  (call
    target: (identifier) @_target (#eq? @_target "describe")
    (arguments . (string (quoted_content) @namespace.name))
    (do_block)
  ) @namespace.definition

  ;; Test blocks (dynamic)
  (call
    target: (identifier) @_target (#any-of? @_target ]] .. test_block_ids .. [[)
    (arguments . [
      (string (interpolation)) ;; String with interpolations
      (identifier) ;; Single variable as name
      (call target: (identifier) @_target2 (#eq? @_target2 "inspect")) ;; Inspect call as name
      (sigil . (sigil_name) @_sigil_name (interpolation)) (#any-of? @_sigil_name "s") ;; Sigil ~s, with interpolations
    ] @dytest.name)
    (do_block)?
  ) @dytest.definition

  ;; Test blocks (static)
  (call
    target: (identifier) @_target (#any-of? @_target ]] .. test_block_ids .. [[)
    (arguments . [
      (string . (quoted_content) @test.name .) ;; Simple string
      (string . (quoted_content) [(escape_sequence) (quoted_content)]+ .) @test.name ;; String with escape sequences
      (sigil . (sigil_name) @_sigil_name . (quoted_content) @test.name .) (#any-of? @_sigil_name "s" "S") ;; Sigil ~s and ~S, no interpolations
    ]
    )
    (do_block)?
  ) @test.definition

  ;; Doctests
  ;; The word doctest is included in the name to make it easier to notice
  (call
    target: (identifier) @_target (#eq? @_target "doctest")
  ) @test.name @test.definition
  ]]
