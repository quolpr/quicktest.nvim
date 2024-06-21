local Job = require("plenary.job")
local json5 = require("json5")

local M = {}

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

return M
