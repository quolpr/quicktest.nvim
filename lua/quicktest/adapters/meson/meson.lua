local Job = require("plenary.job")
local json5 = require("json5")

local M = {}

--- Obtain build definitions for all targets.
--- Calls 'meson introspect --targets build' under the hood from the current directory.
--- This function returns a table with parsed JSON data
---@return table
function M.get_targets()
  local output = ""
  local job = Job:new({

    command = "meson",
    args = { "introspect", "--targets", "build" },
    on_stdout = function(_, data)
      output = output .. data
    end,
    on_stderr = function(_, data)
      print(data)
    end,
    on_exit = function(_, return_val)
      if return_val ~= 0 then
        print("meson introspect returned: " .. tostring(return_val))
      end
    end,
  })
  job:start()
  Job.join(job)
  return json5.parse(output)
end

---@class CompileResult
---@field return_val integer
---@field text string[]

--- Compile the project
--- Calls 'meson -C compile build' under the hood from the current directory
--- @return CompileResult
function M.compile()
  local build_out = {}
  local retval = -1

  local build = Job:new({
    command = "meson",
    args = { "compile", "-C", "build" },
    on_stdout = function(_, data)
      table.insert(build_out, data)
    end,
    on_stderr = function(_, data)
      table.insert(build_out, data)
    end,
    on_exit = function(_, return_val)
      retval = return_val
    end,
  })
  build:start()
  Job.join(build)
  return {
    return_val = retval,
    text = build_out,
  }
end

return M
