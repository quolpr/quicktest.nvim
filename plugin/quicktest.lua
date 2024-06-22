vim.api.nvim_create_user_command("C", function()
  require("lazy.core.loader").reload("quicktest.nvim")

  -- require("quicktest").open_win("popup")
  -- local module = require("quicktest.module")
  --
  -- module.run(require("quicktest.adapters.golang"), {
  --   func_names = { "TestSum" },
  --   sub_func_names = {},
  --   cwd = "/Users/quolpr/.config/nvim/go_test",
  --   module = "./abc",
  --   bufnr = 0,
  -- })
end, {})

-- vim.api.nvim_create_user_command("Go", function()
--   local module = require("quicktest.module")
--
--   module.run(require("quicktest.adapters.golang"), {
--     func_names = { "TestSum" },
--     sub_func_names = {},
--     cwd = "/Users/quolpr/.config/nvim/go_test",
--     module = "./abc",
--     bufnr = 0,
--   })
--   -- M.run(api.nvim_get_current_buf(), { "TestSum" }, nil, "/Users/quolpr/.config/nvim/go_test", "./abc")
--   -- require("plenary.reload").reload_module("quicktest", false)
--   -- require("lazy.core.loader").reload("quicktest.nvim")
-- end, {})
