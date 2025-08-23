local M = {}

--- @param func_names string[]
--- @param sub_func_names string[]
--- @return string?
local function build_run_arg(func_names, sub_func_names)
  if #func_names == 0 then
    return nil
  end

  local escaped_func_names = vim.tbl_map(function(v)
    return string.format([[^\Q%s\E$]], v)
  end, func_names)

  local run_arg = vim.fn.join(escaped_func_names, "|")

  if #func_names == 1 and #sub_func_names > 0 then
    local subtest_name = string.match(sub_func_names[1], [["(.+)"]])
    if subtest_name then
      run_arg = vim.fn.join({ run_arg, string.format([[^\Q%s\E$]], subtest_name) }, "/")
    end
  end

  return run_arg
end

--- @param module string
--- @param func_names string[]
--- @param sub_func_names string[]
--- @param additional_args string[]
--- @return string[]
function M.build_args(module, func_names, sub_func_names, additional_args)
  local args = {
    "test",
  }

  if module and module ~= "." then
    table.insert(args, module)
  end

  local run_arg = build_run_arg(func_names, sub_func_names)
  if run_arg then
    table.insert(args, string.format("-run=%s", run_arg))
  end

  table.insert(args, "-v")
  table.insert(args, "-json")

  args = vim.list_extend(args, additional_args)

  return args
end

--- @param func_names string[]
--- @param sub_func_names string[]
--- @param additional_args string[]
--- @return string[]
function M.build_dap_args(func_names, sub_func_names, additional_args)
  local test_args = {}

  local run_arg = build_run_arg(func_names, sub_func_names)
  if run_arg then
    table.insert(test_args, "-test.run=" .. run_arg)
  end

  table.insert(test_args, "-test.v")
  test_args = vim.list_extend(test_args, additional_args)

  return test_args
end

return M
