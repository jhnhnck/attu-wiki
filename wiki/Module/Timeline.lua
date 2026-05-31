-- Module:Timeline
-- CSS-div timeline renderer for the Attu Project wiki.
-- Replaces EasyTimeline (PNG) with inline HTML/CSS that survives MediaWiki's sanitizer.
--
-- Invoke:
--   {{#invoke:Timeline|main
--    |data=List_of_IgRS_Speakers_by_time_as_Speaker/Timeline
--    |period_start=1-1 1 PC
--    |period_end=present
--   }}
--
-- Data subpage may contain:
--   {{TimelineOption|calendar=haracalnde}}  (default; also: deysachni)
--   {{TimelineColor|id|#RRGGBB|Legend Name}}
--   {{TimelineBar|bar_id|label|color_id|start|end[|narrow]}}

local Cal = require("Module:AttuCalendar")

local M = {}

-- Layout constants (mirror EasyTimeline PlotArea / barincrement).
local LABEL_W  = 150   -- px: left label column
local BAR_W    = 1150  -- px: bar area width
local CANVAS_W = LABEL_W + BAR_W
local ROW_H    = 20    -- px: row height (barincrement)
local BAR_H    = 16    -- px: full bar (ROW_H - 2*2)
local NARROW_H = 6     -- px: narrow overlay height

-- Nation colour map — muted palette derived from flag hues.
local COLORS = {
    utlia      = "#C0392B",  -- deep red
    akaria     = "#148F77",  -- dark teal
    okrit      = "#1E8449",  -- forest green
    tietero    = "#1A5276",  -- dark blue
    niueyjar   = "#7D3C98",  -- purple
    deysachin  = "#D35400",  -- burnt orange
    nongba     = "#E87C8A",  -- rose
    eee        = "#C9A800",  -- dark amber
    casea      = "#2E86C1",  -- medium sky blue
    faltir     = "#9E7B5A",  -- tan/brown
    kel        = "#2E4057",  -- dark slate
    spyron     = "#7F8C8D",  -- steel gray
    joy        = "#B7770D",  -- dark gold
    larossa    = "#1A237E",  -- navy
    kalam      = "#0E9AA7",  -- cyan-teal
    hapsaw     = "#B03A7A",  -- deep rose/magenta
    steam      = "#6B6B00",  -- olive
    tvaqi      = "#2AA198",  -- solarized cyan (distinct from akaria/kalam)
    walst      = "#7B241C",  -- dark maroon
}

-- Nation display names in legend order.
local NATIONS = {
    { id = "utlia",     name = "Utlia" },
    { id = "akaria",    name = "Akaria" },
    { id = "okrit",     name = "Okrit" },
    { id = "tietero",   name = "Tietero" },
    { id = "niueyjar",  name = "Niueyjar" },
    { id = "deysachin", name = "Deysachin" },
    { id = "nongba",    name = "Nongba" },
    { id = "eee",       name = "eee" },
    { id = "casea",     name = "Casea" },
    { id = "faltir",    name = "Faltir" },
    { id = "kel",       name = "Kelelemi" },
    { id = "spyron",    name = "Spyron" },
    { id = "joy",       name = "Joy" },
    { id = "larossa",   name = "La Rossa" },
    { id = "kalam",     name = "Kalam" },
    { id = "hapsaw",    name = "Hapshaw" },
    { id = "steam",     name = "Steamworks" },
    { id = "tvaqi",     name = "T'vaqi" },
    { id = "walst",     name = "Wälstanland" },
}

-- ---------- date parsers ----------

-- Parse a Deysachni date (year.month.day, year.month, or year) into a
-- fractional coordinate. Deysachni years are an independent system with no
-- fixed offset to PC; the numbers are used as raw coordinates on the axis.
-- "present" returns math.huge so frac_of clamps it to the end of the period.
local function parse_deysachni(s)
    s = mw.text.trim(s)
    if s == "present" then return math.huge end
    local y, mo, d
    y, mo, d = s:match("^(-?%d+)%.(%d+)%.(%d+)$")
    if y then
        y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    else
        y, mo = s:match("^(-?%d+)%.(%d+)$")
        if y then y, mo, d = tonumber(y), tonumber(mo), 1 end
    end
    if not y then
        local raw = s:match("^(-?%d+)$")
        if raw then y, mo, d = tonumber(raw), 1, 1 end
    end
    if not y then error("unrecognised Deysachni date: " .. tostring(s)) end
    local frac = ((mo - 1) * 30 + (d - 1)) / 360
    if y > 0 then return y + frac else return y - frac end
end

local DATE_PARSERS = {
    haracalnde = function(s) return Cal.parse_date(s) end,
    deysachni  = parse_deysachni,
}

-- ---------- data subpage ----------

local function get_page_content(title)
    local t = mw.title.new(title)
    return t and t:getContent() or nil
end

-- Parse the data subpage. Recognises three template calls:
--
--   {{TimelineOption|calendar=haracalnde}}
--   {{TimelineColor|id|#hex|Legend Name}}
--   {{TimelineBar|bar|label|color|start|end[|narrow]}}
--
-- Returns rows, segs, ex_colors, ex_nations, options.
local function parse_data(content)
    local rows       = {}
    local row_idx    = {}
    local segs       = {}
    local ex_colors  = {}   -- {id → hex} — page-defined, override hardcoded
    local ex_nations = {}   -- [{id, name}] in declaration order
    local options    = { calendar = "haracalnde" }

    for line in content:gmatch("[^\n]+") do
        -- TimelineOption
        local opt_body = line:match("^%s*{{TimelineOption|(.-)}}%s*$")
        if opt_body then
            for kv in (opt_body .. "|"):gmatch("([^|]+)|") do
                local k, v = kv:match("^([^=]+)=(.*)$")
                if k then
                    options[mw.text.trim(k):lower()] = mw.text.trim(v):lower()
                end
            end
        end

        -- TimelineColor
        local tc_id, tc_hex, tc_name =
            line:match("^%s*{{TimelineColor|([^|]+)|([^|]+)|([^|}]+)}}%s*$")
        if tc_id then
            tc_id   = mw.text.trim(tc_id):lower()
            tc_hex  = mw.text.trim(tc_hex)
            tc_name = mw.text.trim(tc_name)
            if not ex_colors[tc_id] then
                ex_colors[tc_id] = tc_hex
                table.insert(ex_nations, { id = tc_id, name = tc_name })
            end
        end

        -- TimelineBar: 6-arg form first, then 5-arg.
        local bar, label, color, start_s, end_s, narrow =
            line:match("^%s*{{TimelineBar|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|}]+)|([^|}]*)}}%s*$")
        if not bar then
            bar, label, color, start_s, end_s =
                line:match("^%s*{{TimelineBar|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|}]+)}}%s*$")
            narrow = ""
        end
        if bar then
            bar     = mw.text.trim(bar)
            label   = mw.text.trim(label)
            color   = mw.text.trim(color):lower()
            start_s = mw.text.trim(start_s)
            end_s   = mw.text.trim(end_s)
            narrow  = mw.text.trim(narrow or ""):lower()
            if not row_idx[bar] then
                table.insert(rows, { id = bar, label = label })
                row_idx[bar] = #rows
            end
            if not segs[bar] then segs[bar] = {} end
            table.insert(segs[bar], {
                color  = color,
                start  = start_s,
                stop   = end_s,
                narrow = (narrow == "narrow"),
            })
        end
    end
    return rows, segs, ex_colors, ex_nations, options
end

-- ---------- pixel helpers ----------

local function frac_to_x(frac)
    return LABEL_W + math.floor(frac * BAR_W)
end

local function frac_to_w(f1, f2)
    return math.max(2, math.floor((f2 - f1) * BAR_W))
end

-- ---------- renderers ----------

local function render_segs(seg_list, row_top, frac_of, colors)
    -- Render full bars before narrow bars so narrow overlays draw on top.
    local full   = {}
    local narrow = {}
    for _, seg in ipairs(seg_list) do
        local ok,  f1 = pcall(frac_of, seg.start)
        local ok2, f2 = pcall(frac_of, seg.stop)
        if ok and ok2 and f2 > f1 then
            f1 = math.max(0, math.min(1, f1))
            f2 = math.max(0, math.min(1, f2))
            local x   = frac_to_x(f1)
            local w   = frac_to_w(f1, f2)
            local bg  = colors[seg.color] or "#CCCCCC"
            local h, top_off
            if seg.narrow then
                h       = NARROW_H
                top_off = row_top + math.floor((ROW_H - NARROW_H) / 2)
            else
                h       = BAR_H
                top_off = row_top + 2
            end
            local div = string.format(
                '<div style="position:absolute;left:%dpx;top:%dpx;width:%dpx;height:%dpx;background:%s;"></div>',
                x, top_off, w, h, bg
            )
            if seg.narrow then narrow[#narrow + 1] = div
            else               full[#full + 1]     = div
            end
        end
    end
    return table.concat(full) .. table.concat(narrow)
end

local function render_label(label, row_top)
    return string.format(
        '<div style="position:absolute;left:0;top:%dpx;width:%dpx;height:%dpx;'
        .. 'overflow:hidden;white-space:nowrap;font-size:11px;line-height:%dpx;">%s</div>',
        row_top, LABEL_W - 4, ROW_H, ROW_H, label
    )
end

-- Render year axis ticks and major labels.
-- Returns the HTML string and the additional height consumed by the axis.
local function render_axis(ps_num, pe_num, bars_h)
    local out      = {}
    local axis_top = bars_h + 4

    local y_first = math.ceil(ps_num)
    local y_last  = math.floor(pe_num)
    local span    = pe_num - ps_num

    for y = y_first, y_last do
        local frac = (y - ps_num) / span
        if frac >= 0 and frac <= 1 then
            local x        = frac_to_x(frac)
            local is_major = (y % 5 == 0)
            local tick_h   = is_major and 6 or 3

            out[#out + 1] = string.format(
                '<div style="position:absolute;left:%dpx;top:%dpx;width:1px;height:%dpx;background:#555;"></div>',
                x, axis_top, tick_h
            )

            if is_major then
                out[#out + 1] = string.format(
                    '<div style="position:absolute;left:%dpx;top:%dpx;width:40px;'
                    .. 'font-size:10px;text-align:center;white-space:nowrap;">%d</div>',
                    x - 20, axis_top + 8, y
                )
            end
        end
    end

    return table.concat(out), 28  -- axis consumes 28px below bar area
end

local function render_legend(used_colors, colors, nations)
    local items = {}
    for _, n in ipairs(nations) do
        if used_colors[n.id] then
            items[#items + 1] = string.format(
                '<span style="display:inline-block;width:12px;height:12px;'
                .. 'background:%s;margin-right:4px;vertical-align:middle;"></span>%s',
                colors[n.id] or "#ccc", n.name
            )
        end
    end

    local cols    = 4
    local col_w   = 180
    local gap     = 8
    local slot_w  = col_w + gap
    local n_rows  = math.ceil(#items / cols)
    local leg_h   = n_rows * 20
    local leg_w   = cols * slot_w - gap
    local out     = {
        string.format(
            '<div style="position:relative;width:%dpx;height:%dpx;margin-top:8px;">',
            leg_w, leg_h
        )
    }
    for i, item in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        out[#out + 1] = string.format(
            '<div style="position:absolute;left:%dpx;top:%dpx;width:%dpx;'
            .. 'font-size:11px;white-space:nowrap;">%s</div>',
            col * slot_w, row * 20, col_w, item
        )
    end
    out[#out + 1] = '</div>'
    return table.concat(out)
end

-- ---------- main ----------

function M.main(frame)
    local parent = frame:getParent()
    local args = (parent and next(parent.args)) and parent.args or frame.args

    local data_page    = mw.text.trim(args.data         or "")
    local period_start = mw.text.trim(args.period_start or "1-1 1 PC")
    local period_end   = mw.text.trim(args.period_end   or "present")

    if data_page == "" then
        return '<span class="error">Timeline: missing |data= parameter</span>'
    end

    local content = get_page_content(data_page)
    if not content then
        return '<span class="error">Timeline: data page not found: '
            .. mw.text.nowiki(data_page) .. '</span>'
    end

    local rows, segs, ex_colors, ex_nations, options = parse_data(content)
    if #rows == 0 then
        return '<span class="error">Timeline: no TimelineBar entries found</span>'
    end

    -- Build effective color table: page-defined colors extend (and override) hardcoded.
    local colors = {}
    for k, v in pairs(COLORS) do colors[k] = v end
    for k, v in pairs(ex_colors) do colors[k] = v end

    -- Build legend list: hardcoded nations first, then page-defined in declaration order.
    local nations = {}
    local known   = {}
    for _, n in ipairs(NATIONS) do
        known[n.id] = true
        table.insert(nations, n)
    end
    for _, n in ipairs(ex_nations) do
        if not known[n.id] then
            table.insert(nations, n)
        end
    end

    -- Select date parser based on calendar option.
    local parse_date = DATE_PARSERS[options.calendar]
    if not parse_date then
        return '<span class="error">Timeline: unknown calendar "'
            .. mw.text.nowiki(options.calendar) .. '"</span>'
    end

    -- Parse period bounds using the same calendar as the data.
    local ok1, ps_num = pcall(parse_date, period_start)
    local ok2, pe_num = pcall(parse_date, period_end)
    if not (ok1 and ok2) then
        return '<span class="error">Timeline: invalid period_start or period_end</span>'
    end

    -- frac_of: date string → [0,1] fraction within the period.
    local function frac_of(date_str)
        local d    = parse_date(date_str)
        local span = pe_num - ps_num
        if span == 0 then return 0 end
        return (d - ps_num) / span
    end

    -- Collect used colours for the legend.
    local used_colors = {}
    for _, row in ipairs(rows) do
        for _, seg in ipairs(segs[row.id] or {}) do
            used_colors[seg.color] = true
        end
    end

    -- Build the bar canvas.
    local bars_h  = #rows * ROW_H
    local stripes = {}
    local bar_parts = {}

    for i, row in ipairs(rows) do
        local top = (i - 1) * ROW_H
        if i % 2 == 0 then
            stripes[#stripes + 1] = string.format(
                '<div style="position:absolute;left:0;top:%dpx;width:%dpx;height:%dpx;background:rgba(80,130,200,0.18);"></div>',
                top, CANVAS_W, ROW_H
            )
        end
        bar_parts[#bar_parts + 1] = render_label(row.label, top)
        bar_parts[#bar_parts + 1] = render_segs(segs[row.id] or {}, top, frac_of, colors)
    end

    local parts = stripes
    for _, v in ipairs(bar_parts) do parts[#parts + 1] = v end

    -- Vertical line at the TT/PC boundary (year 1.0 in fractional space).
    -- Only meaningful for the Haracalnde calendar.
    local span = pe_num - ps_num
    if options.calendar == "haracalnde" and span > 0 and ps_num <= 1 and pe_num >= 1 then
        local boundary_x = frac_to_x((1.0 - ps_num) / span)
        parts[#parts + 1] = string.format(
            '<div style="position:absolute;left:%dpx;top:0;width:2px;height:%dpx;background:#2C3E50;"></div>',
            boundary_x, bars_h
        )
    end

    local axis_html, axis_extra = render_axis(ps_num, pe_num, bars_h)
    parts[#parts + 1] = axis_html

    local total_h = bars_h + axis_extra
    local canvas = string.format(
        '<div style="position:relative;width:%dpx;height:%dpx;font-family:sans-serif;font-size:12px;">',
        CANVAS_W, total_h
    ) .. table.concat(parts) .. '</div>'

    return '<div style="overflow-x:auto;padding-bottom:16px;">' .. canvas .. render_legend(used_colors, colors, nations) .. '</div>'
        .. '[[Category:Pages with timelines]]'
end

return M
