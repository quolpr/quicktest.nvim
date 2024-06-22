# Quicktest
Quicktest improves your testing experience in real-time with flexible display options like popups or split windows, customized to your workflow preferences. Key features include identifying the nearest function and triggering its test, rerunning previous tests from any location, and live scrolling of results alongside a running timer for immediate feedback.

Currently supported languages: Go, Typescript/Javascript(vitest), Elixir. There is also a template in Readme below about how to create own adapter. Should be pretty easy!

![Example](https://github.com/quolpr/quicktest.nvim/assets/7958527/b3629bc9-2886-468c-a6e2-6b826dc404d0)

## Api 

```lua
local qt = require 'quicktest'

-- Choose your adapter, here all supported adapters are listed
qt.setup({
  adapters = {
    require("quicktest.adapters.golang"),
    require("quicktest.adapters.vitest"),
    require("quicktest.adapters.elixir"),
  }
})

-- Find nearest test under cursor and run in popup
qt.run_line('popup')
-- Find nearest test under cursor and run in split
qt.run_line('split')
-- Find nearest test under cursor and run in currently opened window(popup or split)
qt.run_line()

-- Run all tests of file in popup/split
qt.run_file('popup')
qt.run_file('split')
qt.run_line()

-- Run all tests of current file dir in popup/split
qt.run_dir('popup')
qt.run_dir('split')
qt.run_dir()

-- Run all tests of project in popup/split
qt.run_all('popup')
qt.run_all('split')
qt.run_all()

-- Open or close split/popup if already opened, without running tests.
-- Just open and close window.
qt.toggle_win('popup')
qt.toggle_win('split')

-- Take previous test run and run in popup/split
qt.run_previous('popup')
qt.run_previous('split')
qt.run_previous()
```

## Installation

Supported languages: Go, Typescript/Javascript(vitest)<br>
Feel free to open PR for your language, the plugin API is pretty simple and described in `Building your own plugin` section in this Readme.

Simple configurations:

```lua
local qt = require("quicktest")

-- Choose your adapter, here all supported adapters are listed
qt.setup({
  adapters = {
    require("quicktest.adapters.golang"),
    require("quicktest.adapters.vitest"),
    require("quicktest.adapters.elixir"),
  }
})

vim.keymap.set("n", "<leader>tr", qt.run_line, {
  desc = "[T]est [R]un",
})
vim.keymap.set("n", "<leader>tR", qt.run_file, {
  desc = "[T]est [R]un file",
})
vim.keymap.set("n", "<leader>td", qt.run_dir, {
  desc = "[T]est Run [D]ir",
})
vim.keymap.set("n", "<leader>ta", qt.run_all, {
  desc = "[T]est Run [A]ll",
})
vim.keymap.set("n", "<leader>tR", qt.run_previous, {
  desc = "[T]est Run [P]revious",
})
vim.keymap.set("n", "<leader>tt", function()
  qt.toggle_win("popup")
end, {
  desc = "[T]est [T]oggle popup window",
})
vim.keymap.set("n", "<leader>tt", function()
  qt.toggle_win("split")
end, {
  desc = "[T]est Toggle [S]plit window",
})
```

Using Lazy:

```lua
{
  "quolpr/quicktest.nvim",
  config = function()
    local qt = require("quicktest")

    qt.setup({
      -- Choose your adapter, here all supported adapters are listed
      adapters = {
        require("quicktest.adapters.golang"),
        require("quicktest.adapters.vitest"),
        require("quicktest.adapters.elixir"),
      }
    })
  end,
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
        qt.run_line()
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

        qt.run_file()
      end,
      desc = "[T]est [R]un file",
    },
    {
      '<leader>td',
      function()
        local qt = require 'quicktest'

        qt.run_dir()
      end,
      desc = '[T]est Run [D]ir',
    },
    {
      '<leader>ta',
      function()
        local qt = require 'quicktest'

        qt.run_all()
      end,
      desc = '[T]est Run [A]ll',
    },
    {
      "<leader>tp",
      function()
        local qt = require("quicktest")

        qt.run_previous()
      end,
      desc = "[T]est Run [P]revious",
    },
    {
      "<leader>tt",
      function()
        local qt = require("quicktest")

        qt.toggle_win("popup")
      end,
      desc = "[T]est [T]oggle popup window",
    },
    {
      "<leader>ts",
      function()
        local qt = require("quicktest")

        qt.toggle_win("split")
      end,
      desc = "[T]est Toggle [S]plit window",
    },
  },
}
```

## Features
- **Contextual Test Triggering:** Run tests directly from where your cursor is located or execute all tests in the entire file.
- **Flexible Test Reruns:** Rerun tests from any location, automatically opening a popup or using an existing split view if it's open.
- **Live-Scrolling Results:** Continuously scroll through test results as they are generated.
- **Real-Time Feedback:** View the results of tests immediately as they run, without waiting for the completion of the test suite.
- **Test Duration Timer:** Display a timer to monitor the duration of ongoing tests.
- **Adaptive Display Options:** Instantly displays running test in a popup or uses a split view if already open, adapting to your current setup.

If these features resonate with you, Quicktest might be just what you need!


## Motivation
I like using Neotest, but there are several features that I really miss:

1. Ability to reset test results with each run.
2. Automatically force open a popup when running test, or keep it in split view if split is opened.
3. Stability and performance are not as good as desired. Neotest parses the entire codebase to find tests(correct me if I am wrong), which slows down Neovim.
4. I would appreciate better feedback, such as displaying a timer to show how long the test is running.
5. I want to see test results as they happen, line by line, not just at the end.
6. Make output to automatically scroll while the test is running.
7. Depending on the task, sometimes a popup is best, sometimes a split window. It would be great if the plugin could adapt to the context, potentially displaying results in both views simultaneously.
8. An easy-to-use API for adding new integrations while maintaining flexibility is also needed.

## Building your own adapter

Here is the template of how adapter for any language could be written. For more examples just check `lua/quicktest/adapters`. For tresitter methods investigation you can take code from adapters of neotest from https://github.com/nvim-neotest/neotest?tab=readme-ov-file#supported-runners

```lua
local Job = require("plenary.job")

local M = {
  name = "myadapter",
}
---@class MyRunParams
---@field func_names string[]
---@field bufnr integer
---@field cursor_pos integer[]

--- Optional:
--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@return MyRunParams, nil | string
-- M.build_line_run_params = function(bufnr, cursor_pos)
--   -- You can get current function name to run based on bufnr and cursor_pos
--   -- Check hot it is done for golang at `lua/quicktest/adapters/golang`
--   return {
--     bufnr = bufnr,
--     cursor_pos = cursor_pos,
--     func_names = {},
--     -- Add other parameters as needed
--   }, nil
-- end

--- Optional:
---@param bufnr integer
---@param cursor_pos integer[]
---@return MyRunParams, nil | string
-- M.build_file_run_params = function(bufnr, cursor_pos)
--   return {
--     bufnr = bufnr,
--     cursor_pos = cursor_pos,
--     -- Add other parameters as needed
--   }, nil
-- end

--- Optional:
---@param bufnr integer
---@param cursor_pos integer[]
---@return MyRunParams, nil | string
-- M.build_dir_run_params = function(bufnr, cursor_pos)
--   return {
--     bufnr = bufnr,
--     cursor_pos = cursor_pos,
--     -- Add other parameters as needed
--   }, nil
-- end

--- Optional:
---@param bufnr integer
---@param cursor_pos integer[]
---@return MyRunParams, nil | string
-- M.build_all_run_params = function(bufnr, cursor_pos)
--   return {
--     bufnr = bufnr,
--     cursor_pos = cursor_pos,
--     -- Add other parameters as needed
--   }, nil
-- end

--- Executes the test with the given parameters.
---@param params MyRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local job = Job:new({
    command = "test_command",
    args = { "--some-flag" }, -- Modify based on how your test command needs to be structured
    on_stdout = function(_, data)
      send({ type = "stdout", output = data })
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()

  return job.pid
end

--- Optional: title of the test run
---@param params MyRunParams
-- M.title = function(params)
--   return "Running test"
-- end

--- Optional: handles actions to take after the test run, based on the results.
---@param params any
---@param results any
-- M.after_run = function(params, results)
--   -- Implement actions based on the results, such as updating UI or handling errors
-- end

--- Checks if the adapter is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return vim.endswith(bufname, "test.ts") or vim.endswith(bufname, "test.js")
end

return M
```
