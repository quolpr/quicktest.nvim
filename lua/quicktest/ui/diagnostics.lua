local storage = require("quicktest.storage")

---@class DiagnosticsConfig
---@field enabled boolean

---@param opts DiagnosticsConfig?
---@return table
return function(opts)
  opts = opts or {}

  local M = {}
  M.name = "diagnostics"

  -- Configuration with defaults
  M.config = vim.tbl_deep_extend("force", {
    enabled = true,
  }, opts)

  local ns = vim.api.nvim_create_namespace("quicktest-diagnostics")
  local storage_subscription = nil
  local autocmd_group = nil

  -- Initialize diagnostics and subscribe to storage events
  function M.init()
    if storage_subscription then
      return -- Already initialized
    end

    -- Create autocmd group
    autocmd_group = vim.api.nvim_create_augroup("quicktest-diagnostics", { clear = true })

    storage_subscription = function(event_type, data)
      if event_type == "run_started" then
        -- Clear all diagnostics for new run
        M.clear_all()
      elseif event_type == "test_finished" and data.status == "failed" then
        -- Only update diagnostics when tests are completely done
        -- Check if this is the last test (no more running tests)
        local summary = storage.get_run_summary()
        if summary.running == 0 then
          M.update_all_open_buffers()
        end
      end
    end

    -- Subscribe to storage events
    storage.subscribe(storage_subscription)

    -- Add autocmd for BufEnter to add diagnostics to newly opened buffers
    vim.api.nvim_create_autocmd("BufEnter", {
      group = autocmd_group,
      callback = function(args)
        M.update_diagnostics_for_buffer(args.buf)
      end,
    })
  end

  -- Clean up diagnostics subscription and autocmds
  function M.cleanup()
    if storage_subscription then
      storage.unsubscribe(storage_subscription)
      storage_subscription = nil
    end

    if autocmd_group then
      vim.api.nvim_del_augroup_by_id(autocmd_group)
      autocmd_group = nil
    end

    M.clear_all()
  end

  -- Clear diagnostics for all buffers
  function M.clear_all()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.diagnostic.set(ns, bufnr, {}, {})
      end
    end
  end

  -- Update diagnostics for a specific buffer
  function M.update_diagnostics_for_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local file_path = vim.api.nvim_buf_get_name(bufnr)
    if not file_path or file_path == "" then
      return
    end

    local diagnostics = {}
    local results = storage.get_current_results()

    for _, result in ipairs(results) do
      if result.assert_failures then
        for _, failure in ipairs(result.assert_failures) do
          if failure.full_path == file_path then
            -- Format message as "Error: Messages" where both parts are optional
            local error_part = failure.error_message or ""
            local message_part = failure.message or ""
            local formatted_message

            if error_part ~= "" and message_part ~= "" then
              formatted_message = string.format("%s: %s", error_part, message_part)
            elseif error_part ~= "" then
              formatted_message = error_part
            elseif message_part ~= "" then
              formatted_message = message_part
            else
              formatted_message = "Assert failed"
            end

            local diagnostic = {
              lnum = failure.line - 1, -- Convert to 0-based
              col = 0,
              severity = vim.diagnostic.severity.ERROR,
              message = formatted_message,
              source = "quicktest",
              user_data = {
                test_name = result.name,
                type = "assert_failure",
              },
            }
            table.insert(diagnostics, diagnostic)
          end
        end
      end
    end

    -- Set diagnostics for the buffer
    vim.diagnostic.set(ns, bufnr, diagnostics, {})
  end

  -- Update diagnostics for all currently open buffers
  function M.update_all_open_buffers()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        M.update_diagnostics_for_buffer(bufnr)
      end
    end
  end

  return M
end
