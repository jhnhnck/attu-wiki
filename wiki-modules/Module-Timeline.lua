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

local Cal = require("Module:AttuCalendar")

local M = {}

-- Layout constants (mirror EasyTimeline PlotArea / barincrement).
local LABEL_W  = 150   -- px: left label column
local BAR_W    = 1150  -- px: bar area width
local CANVAS_W = LABEL_W + BAR_W
local ROW_H    = 20    -- px: row height (barincrement)
local BAR_H    = 16    -- px: full bar (ROW_H - 2*2)
local NARROW_H = 6     -- px: narrow overlay height

-- Nation colour map (mirrors EasyTimeline ColourMap).
local COLORS = {
    utlia      = "#FF0000",
    akaria     = "#008080",
    okrit      = "#00FF00",
    tietero    = "#0000FF",
    niueyjar   = "#800080",
    deysachin  = "#FFA500",
    nongba     = "#FFB6C1",
    eee        = "#FFFF00",
    casea      = "#87CEEB",
    faltir     = "#D2B48C",
    kel        = "#404040",
    spyron     = "#808080",
    joy        = "#C8A060",
    larossa    = "#000080",
    kalam      = "#00FFFF",
    hapsaw     = "#FF00FF",
    steam      = "#808000",
    tvaqi      = "#4DB3B3",
    walst      = "#B34D4D",
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

-- ---------- data subpage ----------

local function get_page_content(title)
    local t = mw.title.new(title)
    return t and t:getContent() or nil
end

-- Parse {{TimelineBar|bar|label|color|start|end[|narrow]}} lines from raw wikitext.
-- Returns:
--   rows  — list of {id, label} in document order (unique by bar id)
--   segs  — {bar_id → list of {color, start, stop, narrow}}
local function parse_data(content)
    local rows    = {}
    local row_idx = {}
    local segs    = {}

    for line in content:gmatch("[^\n]+") do
        -- Try 6-arg form first, then 5-arg.
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
    return rows, segs
end

-- ---------- pixel helpers ----------

-- Convert a fractional position [0,1] to absolute x in the bar area.
local function frac_to_x(frac)
    return LABEL_W + math.floor(frac * BAR_W)
end

-- Minimum 2px bar width to keep short terms visible.
local function frac_to_w(f1, f2)
    return math.max(2, math.floor((f2 - f1) * BAR_W))
end

-- Convert a date string to a fraction of [ps_num, pe_num] without re-parsing bounds.
local function frac_of(date_str, ps_num, pe_num)
    local d = Cal.parse_date(date_str)
    local span = pe_num - ps_num
    if span == 0 then return 0 end
    return (d - ps_num) / span
end

-- ---------- renderers ----------

local function render_segs(seg_list, row_top, ps_num, pe_num)
    local out = {}
    for _, seg in ipairs(seg_list) do
        local ok, f1 = pcall(frac_of, seg.start, ps_num, pe_num)
        local ok2, f2 = pcall(frac_of, seg.stop,  ps_num, pe_num)
        if ok and ok2 and f2 > f1 then
            f1 = math.max(0, math.min(1, f1))
            f2 = math.max(0, math.min(1, f2))
            local x   = frac_to_x(f1)
            local w   = frac_to_w(f1, f2)
            local bg  = COLORS[seg.color] or "#CCCCCC"
            local h, top_off
            if seg.narrow then
                h       = NARROW_H
                top_off = row_top + math.floor((ROW_H - NARROW_H) / 2)
            else
                h       = BAR_H
                top_off = row_top + 2
            end
            out[#out + 1] = string.format(
                '<div style="position:absolute;left:%dpx;top:%dpx;width:%dpx;height:%dpx;background:%s;"></div>',
                x, top_off, w, h, bg
            )
        end
    end
    return table.concat(out)
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

    -- Draw from the first whole PC year inside the period to the last.
    local y_first = math.ceil(ps_num)
    local y_last  = math.floor(pe_num)
    local span    = pe_num - ps_num

    for y = y_first, y_last do
        local frac = (y - ps_num) / span
        if frac >= 0 and frac <= 1 then
            local x        = frac_to_x(frac)
            local is_major = (y % 5 == 0)
            local tick_h   = is_major and 6 or 3

            -- Tick mark
            out[#out + 1] = string.format(
                '<div style="position:absolute;left:%dpx;top:%dpx;width:1px;height:%dpx;background:#555;"></div>',
                x, axis_top, tick_h
            )

            -- Year label (major ticks only); centred by subtracting half of a 40px box
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

local function render_legend(used_colors)
    local items = {}
    for _, n in ipairs(NATIONS) do
        if used_colors[n.id] then
            items[#items + 1] = string.format(
                '<span style="display:inline-block;width:12px;height:12px;'
                .. 'background:%s;margin-right:4px;vertical-align:middle;"></span>%s',
                COLORS[n.id] or "#ccc", n.name
            )
        end
    end

    local cols    = 4
    local col_w   = math.floor(CANVAS_W / cols)
    local n_rows  = math.ceil(#items / cols)
    local leg_h   = n_rows * 20
    local out     = {
        string.format(
            '<div style="position:relative;width:%dpx;height:%dpx;margin-top:8px;">',
            CANVAS_W, leg_h
        )
    }
    for i, item in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        out[#out + 1] = string.format(
            '<div style="position:absolute;left:%dpx;top:%dpx;width:%dpx;'
            .. 'font-size:11px;overflow:hidden;">%s</div>',
            col * col_w, row * 20, col_w - 4, item
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

    local rows, segs = parse_data(content)
    if #rows == 0 then
        return '<span class="error">Timeline: no TimelineBar entries found</span>'
    end

    -- Parse period bounds once.
    local ok1, ps_num = pcall(Cal.parse_date, period_start)
    local ok2, pe_num = pcall(Cal.parse_date, period_end)
    if not (ok1 and ok2) then
        return '<span class="error">Timeline: invalid period_start or period_end</span>'
    end

    -- Collect used colours for the legend.
    local used_colors = {}
    for _, row in ipairs(rows) do
        for _, seg in ipairs(segs[row.id] or {}) do
            used_colors[seg.color] = true
        end
    end

    -- Build the bar canvas.
    local n_rows  = #rows
    local bars_h  = n_rows * ROW_H
    local parts   = {}

    -- Background rectangle for the bar area.
    parts[#parts + 1] = string.format(
        '<div style="position:absolute;left:%dpx;top:0;width:%dpx;height:%dpx;background:#F2F2F2;"></div>',
        LABEL_W, BAR_W, bars_h
    )

    -- Alternating row backgrounds (every other row slightly darker) — optional polish.
    -- (skipped for now; add in Phase 2 if needed)

    for i, row in ipairs(rows) do
        local top = (i - 1) * ROW_H
        parts[#parts + 1] = render_label(row.label, top)
        parts[#parts + 1] = render_segs(segs[row.id] or {}, top, ps_num, pe_num)
    end

    local axis_html, axis_extra = render_axis(ps_num, pe_num, bars_h)
    parts[#parts + 1] = axis_html

    local total_h = bars_h + axis_extra
    local canvas = string.format(
        '<div style="position:relative;width:%dpx;height:%dpx;font-family:sans-serif;font-size:12px;">',
        CANVAS_W, total_h
    ) .. table.concat(parts) .. '</div>'

    return canvas .. render_legend(used_colors)
end

return M
