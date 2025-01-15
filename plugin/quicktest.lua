-- vim.api.nvim_create_user_command("C", function()
--   require("lazy.core.loader").reload("quicktest.nvim")
--   -- local module = require("quicktest.module")
--   -- module.run(require("quicktest.adapters.golang"), {
--   --   func_names = { "TestSum" },
--   --   sub_func_names = {},
--   --   cwd = "/Users/quolpr/.config/nvim/go_test",
--   --   module = "./abc",
--   --   bufnr = 0,
--   -- })
-- end, {})

---@param existing_array table
---@param n integer
---@return table
local function slice(existing_array, n)
  -- Initialize a new array to store the result
  local new_array = {}

  -- Iterate over the existing array starting from the second element
  for i = n, #existing_array do
    table.insert(new_array, existing_array[i])
  end

  -- Return the new array
  return new_array
end

vim.api.nvim_create_user_command("QuicktestRunLine", function(opts)
  local args = opts.fargs

  local quicktest = require("quicktest")
  quicktest.run_line(args[1], args[2], { additional_args = slice(args, 3) })
end, { nargs = "*" })

vim.api.nvim_create_user_command("QuicktestRunFile", function(opts)
  local args = opts.fargs

  local quicktest = require("quicktest")
  quicktest.run_file(args[1], args[2], { additional_args = slice(args, 3) })
end, { nargs = "*" })

vim.api.nvim_create_user_command("QuicktestRunDir", function(opts)
  local args = opts.fargs

  local quicktest = require("quicktest")
  quicktest.run_dir(args[1], args[2], { additional_args = slice(args, 3) })
end, { nargs = "*" })

vim.api.nvim_create_user_command("QuicktestRunAll", function(opts)
  local args = opts.fargs

  local quicktest = require("quicktest")
  quicktest.run_all(args[1], args[2], { additional_args = slice(args, 3) })
end, { nargs = "*" })
