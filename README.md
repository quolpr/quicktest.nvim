# Quicktest

![Example](https://github.com/quolpr/quicktest.nvim/assets/7958527/b3629bc9-2886-468c-a6e2-6b826dc404d0)


## Motivation
I like using Neotest, but there are several features that I really miss:

1. **Reset Test Results**: Ability to reset test results with each run.
2. **Popup on Rerun**: Automatically force open a popup when running test, or keep it in split view if split is opened.
3. **Performance Issues**: Stability and performance are not as good as desired. Neotest parses the entire codebase to find tests(correct me if I am wrong), which slows down Neovim.
4. **Real-Time Feedback**: I would appreciate better feedback, such as displaying a timer to show how long the test is running.
5. **Live Test Results**: I want to see test results as they happen, line by line, not just at the end.
6. **Scrollable Output**: Enable output to automatically scroll while the test is running.
7. **Adaptive Test Views**: Depending on the task, sometimes a popup is best, sometimes a split window. It would be great if the plugin could adapt to the context, potentially displaying results in both views simultaneously.
8. **Flexible API**: An easy-to-use API for adding new integrations while maintaining flexibility is also needed.

If these features resonate with you, Quicktest might be just what you need!

## Supported languages

Right now only `go` is supported! Feel free to open PR to add other integrations.

## Installation

Using Lazy:

```lua
{
  'quolpr/quicktest.nvim'
  opts = {},
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'm00qek/baleia.nvim',
  },
  keys = function()
    local qt = function()
      return require 'quicktest'
    end

    local keys = {
      {
        '<leader>tr',
        function()
          -- current_win_mode return currently opened panel, split or popup
          qt().run_line(qt().current_win_mode())
          -- You can force open split or popup like this:
          -- qt().run_current('split')
          -- qt().run_current('popup')
        end,
        desc = '[T]est [R]un',
      },
      {
        '<leader>tR',
        function()
          qt().run_file(qt().current_win_mode())
        end,
        desc = '[T]est [R]un file',
      },
      {
        '<leader>tt',
        function()
          qt().toggle_win 'popup'
        end,
        desc = '[T]est [T]toggle result',
      },
      {
        '<leader>ts',
        function()
          qt().toggle_win 'split'
        end,
        desc = '[T]est [S]plit result',
      },

      {
        '<leader>tp',
        function()
          qt().run_previous(qt().current_win_mode())
        end,
        desc = '[T]est [P]revious',
      },
    }

    return keys
  end,
}
```

## Building your own plugin

Here is the template of how plugin for any language could be written. For more examples just check `lua/quicktest/adapters`. For tresitter methods investigation you can take code from adapters of neotest from https://github.com/nvim-neotest/neotest?tab=readme-ov-file#supported-runners

```lua
local Job = require("plenary.job")

local M = {
  name = "generic_test_runner"
}

--- Builds parameters for running tests based on buffer number and cursor position.
--- This function should be customized to extract necessary information from the buffer.
---@param bufnr integer
---@param cursor_pos integer[]
---@return any
M.build_params = function(bufnr, cursor_pos)
  -- You can get current function name to run based on bufnr and cursor_pos
  -- Check hot it is done for golang at `lua/quicktest/adapters/golang`
  return {
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    -- Add other parameters as needed
  }
end

--- Determines if the test can be run with the given parameters.
---@param params any
---@return boolean
M.can_run = function(params)
  -- Implement logic to determine if the test can be run
  return true
end

--- Executes the test with the given parameters.
---@param params any
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local job = Job:new({
    command = "test_command",
    args = {"--some-flag"}, -- Modify based on how your test command needs to be structured
    on_stdout = function(_, data)
      send({type = "stdout", output = data})
    end,
    on_stderr = function(_, data)
      send({type = "stderr", output = data})
    end,
    on_exit = function(_, return_val)
      send({type = "exit", code = return_val})
    end,
  })

  job:start()
  return job.pid -- Return the process ID
end

--- Handles actions to take after the test run, based on the results.
---@param params any
---@param results any
M.after_run = function(params, results)
  -- Implement actions based on the results, such as updating UI or handling errors
end

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  -- Implement logic to determine if the plugin should be active for the given buffer
  return true
end

return M
```
