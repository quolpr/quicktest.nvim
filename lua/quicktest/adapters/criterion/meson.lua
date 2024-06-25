local Job = require("plenary.job")

local M = {}

--- Obtain build definitions for all targets.
--- Calls 'meson introspect --targets build' under the hood from the current directory.
--- This function returns a table with parsed JSON data
--- @param builddir string
---@return table
function M.get_targets(builddir)
  local output = ""
  local retval = -1

  local job = Job:new({

    command = "meson",
    args = { "introspect", "--targets", builddir },
    on_stdout = function(_, data)
      output = output .. data
    end,
    on_stderr = function(_, data)
      print(data)
    end,
    on_exit = function(_, return_val)
      retval = return_val
      if return_val ~= 0 then
        print("Error: " .. output)
      end
    end,
  })
  job:start()
  Job.join(job)

  if retval ~= 0 then
    return {}
  end

  return vim.json.decode(output)
end

---@class CompileResult
---@field return_val integer
---@field text string[]

--- Compile the project
--- Calls 'meson -C compile builddir' under the hood from the current directory
--- @param builddir string
--- @return CompileResult
function M.compile(builddir)
  local build_out = {}
  local retval = -1

  local build = Job:new({
    command = "meson",
    args = { "compile", "-C", builddir },
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
