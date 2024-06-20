-- main module file
local module = require("quicktest.module")

local config = {
  plugins = { require("quicktest.adapters.golang") },
}

---@class MyModule
local M = {}

--- @type QuicktestConfig
M.config = config

---@param args QuicktestConfig?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

M.current_win_mode = function()
  return module.current_win_mode()
end

--- @param mode WinMode
M.open_win = function(mode)
  return module.try_open(mode)
end

--- @param mode WinMode?
M.close_win = function(mode)
  return module.try_close(mode)
end

--- @param mode WinMode?
M.toggle_win = function(mode)
  return module.toggle_win(mode)
end

--- @param mode WinMode?
M.run_previous = function(mode)
  return module.run_previous(mode)
end

--- @param mode WinMode?
M.run_file = function(mode)
  return module.run_file(M.config, mode)
end

--- @param mode WinMode?
M.run_line = function(mode)
  return module.run_line(M.config, mode)
end

-- M.open("split")
-- module.run(require("quicktest.adapters.golang"), {
--   func_names = { "TestSum" },
--   sub_func_names = {},
--   cwd = "/Users/quolpr/.config/nvim/go_test",
--   module = "./abc",
--   bufnr = 0,
-- })
-- M.run(api.nvim_get_current_buf(), { "TestSum" }, nil, "/Users/quolpr/.config/nvim/go_test", "./abc")
-- require("plenary.reload").reload_module("quicktest", false)

local t = {
  "quolpr/quicktest.nvim",
  opts = {},
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "m00qek/baleia.nvim",
  },
  keys = {
    {
      "<leader>tr",
      function()
        local qt = require("quicktest")
        -- current_win_mode return currently opened panel, split or popup
        qt.run_line(qt.current_win_mode())
        -- You can force open split or popup like this:
        -- qt().run_current('split')
        -- qt().run_current('popup')
      end,
      desc = "[T]est [R]un",
    },
    {
      "<leader>tR",
      function()
        local qt = require("quicktest")

        qt.run_file(qt.current_win_mode())
      end,
      desc = "[T]est [R]un file",
    },
    {
      "<leader>tt",
      function()
        local qt = require("quicktest")

        qt.toggle_win("popup")
      end,
      desc = "[T]est [T]toggle result",
    },
    {
      "<leader>ts",
      function()
        local qt = require("quicktest")

        qt.toggle_win("split")
      end,
      desc = "[T]est [S]plit result",
    },

    {
      "<leader>tp",
      function()
        local qt = require("quicktest")

        qt.run_previous(qt.current_win_mode())
      end,
      desc = "[T]est [P]revious",
    },
  },
}

return M
