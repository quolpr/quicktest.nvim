local api = vim.api

local ColoredPrinter = {}
ColoredPrinter.__index = ColoredPrinter

function ColoredPrinter.new()
  local self = setmetatable({}, ColoredPrinter)
  self.color_groups = {}
  self.current_fg = nil
  self.current_bg = nil
  self.current_styles = {}
  self.bright_color_bold = false
  self:setup_highlight_groups()
  return self
end

function ColoredPrinter:get_256_color(index)
  -- Standard 16 colors (0-15)
  if index <= 15 then
    local colors = {
      "#000000", "#800000", "#008000", "#808000", "#000080", "#800080", "#008080", "#c0c0c0",
      "#808080", "#ff0000", "#00ff00", "#ffff00", "#0000ff", "#ff00ff", "#00ffff", "#ffffff"
    }
    return colors[index + 1]
  end

  -- 216 color cube (16-231)
  if index <= 231 then
    local n = index - 16
    local r = math.floor(n / 36)
    local g = math.floor((n % 36) / 6)
    local b = n % 6
    
    local function color_value(c)
      if c == 0 then return 0 end
      return 55 + c * 40
    end
    
    return string.format("#%02x%02x%02x", color_value(r), color_value(g), color_value(b))
  end

  -- Grayscale (232-255)
  if index <= 255 then
    local gray = 8 + (index - 232) * 10
    return string.format("#%02x%02x%02x", gray, gray, gray)
  end

  return "#ffffff" -- fallback
end

function ColoredPrinter:setup_highlight_groups()
  local basic_colors = {
    ["30"] = "Black",
    ["31"] = "Red",
    ["32"] = "Green",
    ["33"] = "Yellow",
    ["34"] = "Blue",
    ["35"] = "Magenta",
    ["36"] = "Cyan",
    ["37"] = "White",
    ["90"] = "Grey",
    ["91"] = "Red",
    ["92"] = "Green",
    ["93"] = "Yellow",
    ["94"] = "Blue",
    ["95"] = "Magenta",
    ["96"] = "Cyan",
    ["97"] = "White",
  }

  for code, color in pairs(basic_colors) do
    local group_name = "QuicktestAnsiColor_" .. code
    vim.cmd(string.format("highlight %s ctermfg=%s guifg=%s", group_name, color:lower(), color))

    self.color_groups[code] = group_name
  end

  -- Add background color groups (40-47, 100-107)
  local bg_colors = {
    ["40"] = "Black",
    ["41"] = "Red", 
    ["42"] = "Green",
    ["43"] = "Yellow",
    ["44"] = "Blue",
    ["45"] = "Magenta",
    ["46"] = "Cyan",
    ["47"] = "White",
    ["100"] = "Grey",
    ["101"] = "Red",
    ["102"] = "Green", 
    ["103"] = "Yellow",
    ["104"] = "Blue",
    ["105"] = "Magenta",
    ["106"] = "Cyan",
    ["107"] = "White",
  }

  for code, color in pairs(bg_colors) do
    local group_name = "QuicktestAnsiBgColor_" .. code
    vim.cmd(string.format("highlight %s ctermbg=%s guibg=%s", group_name, color:lower(), color))
    
    self.color_groups[code] = group_name
  end

  -- Use Normal highlight group directly to ensure proper default colors
  vim.cmd("highlight default QuicktestAnsiColorDefault guifg=NONE guibg=NONE")
  vim.cmd("highlight default link QuicktestAnsiColorDefault Normal")
  self.color_groups["default"] = "QuicktestAnsiColorDefault"
end

function ColoredPrinter:get_or_create_color_group(fg, bg, styles)
  -- If no colors or styles are set, use the default group
  if not fg and not bg and (#styles == 0) then
    return self.color_groups["default"]
  end

  local function sanitize(str)
    if str then
      -- Replace # with "hex" and any non-alphanumeric characters with their hex code
      return str:gsub("#", ""):gsub("[^%w]", function(c)
        return string.format("%02x", string.byte(c))
      end)
    end
    return ""
  end

  local unique_styles = {}
  for _, style in ipairs(styles) do
    unique_styles[style] = true
  end
  unique_styles = vim.tbl_keys(unique_styles)
  -- sort and uniqize the styles
  styles = vim.tbl_filter(function(s)
    return s ~= ""
  end, unique_styles)
  table.sort(styles)

  local color_key = table.concat(
    vim.tbl_filter(function(s)
      return s ~= ""
    end, { sanitize(fg), sanitize(bg), table.concat(styles, "_") }),
    "_"
  )

  if not self.color_groups[color_key] then
    local group_name = "QuicktestAnsiColor"

    if #color_key > 0 then
      group_name = group_name .. "_" .. color_key
    end

    local cmd = "highlight " .. group_name
    local start_cmd = cmd

    if fg then
      if fg:match("^#") then
        cmd = cmd .. string.format(" guifg=%s", fg)
      elseif self.color_groups[fg] then
        local fg_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(self.color_groups[fg])), "fg#")
        if fg_color and fg_color ~= "" then
          cmd = cmd .. " guifg=" .. fg_color
        end
      end
    end

    if bg then
      if bg:match("^#") then
        cmd = cmd .. string.format(" guibg=%s", bg)
      elseif self.color_groups[bg] then
        local bg_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(self.color_groups[bg])), "bg#")
        if bg_color and bg_color ~= "" then
          cmd = cmd .. " guibg=" .. bg_color
        end
      end
    end

    if #styles > 0 then
      cmd = cmd .. " gui=" .. table.concat(styles, ",")
    end

    if start_cmd ~= cmd then
      local success, err = pcall(vim.cmd, cmd)
      if not success then
        -- Fallback to basic highlight if command fails
        vim.cmd("highlight " .. group_name)
      end
    end

    self.color_groups[color_key] = group_name
  end
  return self.color_groups[color_key]
end

function ColoredPrinter:parse_colors(line)
  local result = {}
  local highlights = {}
  local i = 1
  local color_start = 0

  local function update_color()
    if #result > color_start then
      local group = self:get_or_create_color_group(self.current_fg, self.current_bg, self.current_styles)
      table.insert(highlights, { group = group, start = color_start, end_ = #result })
    end
    color_start = #result
  end

  while i <= #line do
    if line:sub(i, i) == "\27" and line:sub(i + 1, i + 1) == "[" then
      local j = line:find("m", i + 2)
      if j then
        update_color()

        local codes = vim.split(line:sub(i + 2, j - 1), ";")
        local index = 1
        while index <= #codes do
          local code = tonumber(codes[index])
          -- Skip empty or invalid codes
          if not code then
            index = index + 1
            goto continue
          end
          if code == 0 then
            self.current_fg, self.current_bg = nil, nil
            self.current_styles = {}
            self.bright_color_bold = false
          elseif code == 1 then
            table.insert(self.current_styles, "bold")
            -- This is explicit bold, not from bright colors
            self.bright_color_bold = false
          elseif code == 2 then
            -- Dim/faint - implement by setting a gray foreground color
            self.current_fg = "#808080"
          elseif code == 3 then
            table.insert(self.current_styles, "italic")
          elseif code == 4 then
            table.insert(self.current_styles, "underline")
          elseif code == 5 or code == 6 then
            -- Blink - not supported in most terminals/Neovim, skip
          elseif code == 7 then
            table.insert(self.current_styles, "reverse")
          elseif code == 8 then
            -- Conceal - not directly supported as gui attribute, skip
          elseif code == 9 then
            table.insert(self.current_styles, "strikethrough")
          elseif code == 21 then
            table.insert(self.current_styles, "undercurl")
          elseif code == 22 then
            self.current_styles = vim.tbl_filter(function(s) return s ~= "bold" end, self.current_styles)
            -- Reset dim color if it was set
            if self.current_fg == "#808080" then
              self.current_fg = nil
            end
          elseif code == 23 then
            self.current_styles = vim.tbl_filter(function(s) return s ~= "italic" end, self.current_styles)
          elseif code == 24 then
            self.current_styles = vim.tbl_filter(function(s) return s ~= "underline" and s ~= "undercurl" end, self.current_styles)
          elseif code == 25 then
            -- Reset blink (not supported anyway)
          elseif code == 27 then
            self.current_styles = vim.tbl_filter(function(s) return s ~= "reverse" end, self.current_styles)
          elseif code == 28 then
            -- Reset conceal (not supported anyway)
          elseif code == 29 then
            self.current_styles = vim.tbl_filter(function(s) return s ~= "strikethrough" end, self.current_styles)
          elseif code == 39 then
            self.current_fg = nil  -- Reset foreground to default
            -- If bold was auto-added by bright color, remove it
            if self.bright_color_bold then
              self.current_styles = vim.tbl_filter(function(s) return s ~= "bold" end, self.current_styles)
              self.bright_color_bold = false
            end
          elseif code == 49 then
            self.current_bg = nil  -- Reset background to default
          elseif code >= 30 and code <= 37 then
            self.current_fg = tostring(code)
          elseif code >= 40 and code <= 47 then
            self.current_bg = tostring(code)
          elseif code >= 90 and code <= 97 then
            self.current_fg = tostring(code)
            if not vim.tbl_contains(self.current_styles, "bold") then
              table.insert(self.current_styles, "bold")
            end
            -- Mark that this bold was auto-added by bright color
            self.bright_color_bold = true
          elseif code >= 100 and code <= 107 then
            self.current_bg = tostring(code)
          elseif code == 38 or code == 48 then
            if codes[index + 1] == "2" then
              if #codes >= index + 4 then
                local r = tonumber(codes[index + 2])
                local g = tonumber(codes[index + 3])
                local b = tonumber(codes[index + 4])
                if r and g and b then
                  if code == 38 then
                    self.current_fg = string.format("#%02x%02x%02x", r, g, b)
                  else
                    self.current_bg = string.format("#%02x%02x%02x", r, g, b)
                  end
                  index = index + 4
                end
              end
            elseif codes[index + 1] == "5" then
              if #codes >= index + 2 then
                local color_index = tonumber(codes[index + 2])
                if color_index and color_index >= 0 and color_index <= 255 then
                  local color_hex = self:get_256_color(color_index)
                  if code == 38 then
                    self.current_fg = color_hex
                  else
                    self.current_bg = color_hex
                  end
                  index = index + 2
                end
              end
            end
          end
          index = index + 1

          ::continue::
        end

        i = j + 1
      else
        i = i + 1
      end
    else
      table.insert(result, line:sub(i, i))
      i = i + 1
    end
  end

  update_color()

  return table.concat(result), highlights
end

local function get_highlight_def(group)
  if group == "AnsiColor" then
    return "highlight AnsiColor"
  end

  local hl = vim.api.nvim_get_hl_by_name(group, true)
  local hl_string = string.format("highlight %s", group)

  if hl.foreground then
    hl_string = hl_string .. string.format(" guifg=#%06x", hl.foreground)
  end

  if hl.background then
    hl_string = hl_string .. string.format(" guibg=#%06x", hl.background)
  end

  if hl.special then
    hl_string = hl_string .. string.format(" guisp=#%06x", hl.special)
  end

  local gui_attrs = {}
  for _, attr in ipairs({ "bold", "italic", "underline", "undercurl", "reverse", "inverse", "standout" }) do
    if hl[attr] then
      table.insert(gui_attrs, attr)
    end
  end

  if #gui_attrs > 0 then
    hl_string = hl_string .. " gui=" .. table.concat(gui_attrs, ",")
  end

  return hl_string
end

function ColoredPrinter:set_next_lines(lines, buf, lines_count)
  local parsed_lines = {}
  local parsed_highlights = {}

  for _, line in ipairs(lines) do
    local plain_line, highlights = self:parse_colors(line)
    table.insert(parsed_lines, plain_line)
    table.insert(parsed_highlights, highlights)
  end

  api.nvim_buf_set_lines(buf, lines_count, -1, false, parsed_lines)

  for i, hl in ipairs(parsed_highlights) do
    for _, h in ipairs(hl) do
      -- print("[" .. h.start .. "," .. h.end_ .. ")", get_highlight_def(h.group))

      api.nvim_buf_add_highlight(buf, -1, h.group, lines_count - 1 + i, h.start, h.end_)
    end
  end

  -- for _, line in ipairs(lines) do
  --   self:set_next_line(line, buf)
  -- end
end

function ColoredPrinter:debug_print_colors(line)
  local plain_line, highlights = self:parse_colors(line)
  print("Original line:", line)
  print("Parsed line:", plain_line)
  for _, hl in ipairs(highlights) do
    print("[" .. hl.start .. "," .. hl.end_ .. ")", get_highlight_def(hl.group))
  end
end

return ColoredPrinter
