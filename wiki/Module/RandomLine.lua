-- Module:RandomLine
-- Returns one line from a page, rotating every 12 hours.
-- Usage: {{#invoke:RandomLine|line|Page name}}

local M = {}

-- 12-hour window index (changes at 00:00 and 12:00 UTC).
local function window()
    return math.floor(os.time() / 43200)
end

function M.line(frame)
    local page_name = mw.text.trim(frame.args[1] or "")
    if page_name == "" then
        return '<span class="error">RandomLine: page name required</span>'
    end

    local title = mw.title.new(page_name)
    if not title then
        return '<span class="error">RandomLine: invalid page name</span>'
    end

    local content = title:getContent()
    if not content or content == "" then
        return '<span class="error">RandomLine: page not found or empty</span>'
    end

    local lines = {}
    for line in content:gmatch("[^\n]+") do
        local trimmed = mw.text.trim(line)
        if trimmed ~= "" and not trimmed:match("^==") then
            table.insert(lines, trimmed)
        end
    end

    if #lines == 0 then
        return '<span class="error">RandomLine: no non-empty lines found</span>'
    end

    math.randomseed(window())
    math.random()  -- discard first value; Lua LCG has weak low bits on seed
    return lines[math.random(#lines)]
end

return M
