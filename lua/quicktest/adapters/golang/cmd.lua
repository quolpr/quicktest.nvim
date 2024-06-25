local M = {}

--- @params module string
--- @params func_names string[]
--- @params sub_func_names string[]
--- @params additional_args string[]
--- @return string[]
function M.build_args(module, func_names, sub_func_names, additional_args)
  local args = {
    "test",
  }

  if module and module ~= "." then
    table.insert(args, module)
  end

  local run_arg = nil

  if #func_names > 0 then
    func_names = vim.tbl_map(function(v)
      return string.format([[^\Q%s\E$]], v)
    end, func_names)

    run_arg = string.format([[%s]], vim.fn.join(func_names, "|"))
  end

  if #func_names == 1 and #sub_func_names > 0 then
    local subtest_name = string.match(sub_func_names[1], [["(.+)"]])

    if subtest_name then
      run_arg = vim.fn.join({ run_arg, string.format([[^\Q%s\E$]], subtest_name) }, "/")
    end
  end

  if run_arg then
    table.insert(args, string.format("-run=%s", run_arg))
  end
  table.insert(args, "-v")
  table.insert(args, "-json")

  print(vim.inspect(additional_args))
  print(vim.inspect(args))
  args = vim.list_extend(args, additional_args)

  return args
end

return M
