-- Module:AttuCalendar
-- Haracalnde calendar arithmetic for the Attu Project wiki.
-- Epoch constants mirror scripts/misc/current_year.py; update both when /fix epoch runs.

local M = {}

local EPOCH_UNIX = 1772229600  -- Unix timestamp of the epoch snapshot
local EPOCH_YEAR = 76          -- in-universe PC year at that snapshot
local YEAR_DAYS  = 21          -- real days per in-universe year

-- Return the current in-universe year (PC, integer).
function M.current_year()
    local elapsed_days = math.floor((os.time() - EPOCH_UNIX) / 86400)
    return EPOCH_YEAR + math.floor(elapsed_days / YEAR_DAYS)
end

-- Parse a Haracalnde date string and return a fractional year.
--
-- Accepts:
--   "d-m y PC"  → positive fractional year (1 PC = 1.0, no year 0)
--   "d-m y TT"  → negative fractional year (1 TT = -1.0)
--   "present"   → current_year() as an integer (no fractional part)
--
-- The fractional part encodes month and day within the year so that dates
-- can be compared and used for pixel calculations.
function M.parse_date(s)
    s = mw.text.trim(s)
    if s:lower() == "present" then
        return M.current_year()
    end
    local d, mo, y, era = s:match("^(%d+)-(%d+)%s+(%d+)%s+(%a+)$")
    if not d then
        error("AttuCalendar: cannot parse date: " .. tostring(s))
    end
    d  = tonumber(d)
    mo = tonumber(mo)
    y  = tonumber(y)
    -- No year 0: 1 TT → -1, 1 PC → 1.
    if era:upper() == "TT" then
        y = -y
    elseif era:upper() ~= "PC" then
        error("AttuCalendar: unknown era: " .. era)
    end
    -- Fractional offset within year: months are 1-indexed, days are 1-indexed.
    -- 12 months × 30 days = 360 days/year.
    local frac = (mo - 1) / 12 + (d - 1) / 360
    return y + frac
end

-- Convert a date string to a fraction in [0, 1] relative to [period_start, period_end].
-- Returns nil if the date falls outside the period (clamped to 0 or 1 would hide bugs).
function M.to_frac(date_str, period_start_str, period_end_str)
    local d     = M.parse_date(date_str)
    local ps    = M.parse_date(period_start_str)
    local pe    = M.parse_date(period_end_str)
    local span  = pe - ps
    if span == 0 then return 0 end
    return (d - ps) / span
end

return M
