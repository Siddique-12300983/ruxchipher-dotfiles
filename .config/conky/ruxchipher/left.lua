-- ruxchipher LEFT: greeting + tip, mission tracker, weather + calendar.
-- The gap between the greeting and the panels leaves the wallpaper's Arch logo visible.
local DIR = os.getenv('HOME') .. '/.config/conky/ruxchipher/'
local U = dofile(DIR .. 'common.lua')
local col, text, rgba = U.col, U.text, U.rgba

local PW, PH = 360, 400        -- panel size
local PY = 372                 -- panel top (below the Arch logo)
local MX, WX = 0, 376          -- mission / weather panel x

---------------------------------------------------------------- content

local TIPS = {
    'Every attack you run in the lab should end with a detection you can show for it.',
    'Event ID 4769 with ticket encryption 0x17 (RC4) is a classic Kerberoasting tell.',
    'Defenders think in lists. Attackers think in graphs. — John Lambert',
    'Logs you never read are just disk usage. Review one source every day.',
    'Service accounts with SPNs need long, random passwords, or better, gMSAs.',
    'Snapshot the lab before every attack. Rolling back beats rebuilding.',
    'Sysmon Event ID 1 (process creation) answers most "what ran?" questions.',
    'Least privilege first. Detection is the backup plan, not the plan.',
    'Document as you go: future you is the first reader of your write-up.',
    'If you can explain the attack in plain words, you can write the detection.',
    'Purple team = red executes, blue observes, both improve the control together.',
    'Tune alerts until each one is worth waking up for.',
    'MITRE ATT&CK T1558.003 is Kerberoasting. Map every lab exercise to a technique.',
    'Baseline normal first. You cannot spot weird without knowing boring.',
}

local function greeting()
    local h = tonumber(os.date('%H'))
    if h < 5 then return 'Burning the midnight oil,' end
    if h < 12 then return 'Good morning,' end
    if h < 18 then return 'Good afternoon,' end
    return 'Good evening,'
end

---------------------------------------------------------------- mission data

local mission = { goal = 'mission', deadline = '2027-01-01', repo = nil, items = {} }
local commits = {}    -- 'YYYY-MM-DD' -> count

local function load_mission()
    local raw = U.readf(DIR .. 'mission.txt')
    if not raw then return end
    mission.items = {}
    for line in raw:gmatch('[^\n]+') do
        local k, v = line:match('^(%w+):%s*(.-)%s*$')
        local box, label = line:match('^%[(.)%]%s*(.+)$')
        if box then
            mission.items[#mission.items + 1] = { done = box:lower() == 'x', label = label }
        elseif k and not line:match('^#') then
            mission[k] = v
        end
    end
end

local function load_commits()
    commits = {}
    if not mission.repo then return end
    local repo = mission.repo:gsub('^~', os.getenv('HOME'))
    for _, d in ipairs(U.lines("git -C '" .. repo .. "' log --since=40.days --format=%cd --date=short 2>/dev/null")) do
        commits[d] = (commits[d] or 0) + 1
    end
end

local function day_key(offset)
    return os.date('%Y-%m-%d', os.time() - offset * 86400)
end

local function streak()
    local start = commits[day_key(0)] and 0 or 1
    local n = 0
    while commits[day_key(start + n)] do n = n + 1 end
    return n
end

local function days_left()
    local y, m, d = mission.deadline:match('(%d+)-(%d+)-(%d+)')
    if not y then return 0 end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
    return math.max(0, math.ceil((t - os.time()) / 86400))
end

---------------------------------------------------------------- weather data

local ICON = {
    sun = '\u{F0599}', moon = '\u{F0594}', partly = '\u{F0595}', cloud = '\u{F0590}',
    fog = '\u{F0591}', rain = '\u{F0597}', pour = '\u{F0596}', storm = '\u{F0593}', snow = '\u{F0598}',
}

local function weather_icon(code, night)
    code = tonumber(code) or 0
    if code == 113 then return night and ICON.moon or ICON.sun, col.yellow end
    if code == 116 then return ICON.partly, col.sub end
    if code == 119 or code == 122 then return ICON.cloud, col.sub end
    if code == 143 or code == 248 or code == 260 then return ICON.fog, col.muted end
    if code == 200 or (code >= 386 and code <= 395) then return ICON.storm, col.purple end
    if (code >= 179 and code <= 230) or (code >= 320 and code <= 377 and code ~= 353 and code ~= 356 and code ~= 359) then
        return ICON.snow, col.fg
    end
    if code == 305 or code == 308 or code == 356 or code == 359 then return ICON.pour, col.blue end
    return ICON.rain, col.cyan
end

local weather = {}

local function load_weather()
    local raw = U.readf(os.getenv('HOME') .. '/.cache/ruxchipher/weather.txt')
    if not raw then return end
    weather = {}
    for k, v in raw:gmatch('(%w+)=([^\n]*)') do weather[k] = v end
end

local function fetch_weather()
    os.execute('python3 -I ' .. DIR .. 'weather.py >/dev/null 2>&1 &')
end

---------------------------------------------------------------- drawing

local function draw_greeting(cr)
    text(cr, greeting(), 12, 40, 26, col.sub, { font = U.FONT_LIGHT, shadow = true })
    text(cr, 'Siddique.', 10, 104, 62, col.fg, {
        bold = true, shadow = true,
        pattern = U.grad(10, 0, 340, 0, col.cyan, col.purple),
    })
    text(cr, 'ruxchipher  ·  purple team in training', 14, 132, 12, col.muted, { shadow = true })

    local tip = TIPS[(os.time() // 900) % #TIPS + 1]
    local lines = U.wrap(cr, tip, 13, 560)
    local top = 148
    rgba(cr, col.purple, 0.8)
    U.rrect(cr, 12, top, 2, #lines * 20 + 6, 1)
    cairo_fill(cr)
    for i, l in ipairs(lines) do
        text(cr, l, 26, top + 2 + i * 20 - 4, 13, col.sub, { shadow = true })
    end
end

local function draw_mission(cr)
    local x, y = MX, PY
    U.panel(cr, x, y, PW, PH)
    U.header(cr, x + 20, y + 30, PW, 'MISSION', mission.goal)

    -- countdown
    local left = days_left()
    local nw = text(cr, tostring(left), x + 20, y + 92, 48, col.fg, {
        bold = true, pattern = U.grad(x + 20, 0, x + 140, 0, col.cyan, col.purple),
    })
    text(cr, 'days', x + 28 + nw, y + 72, 12, col.sub)
    text(cr, 'until ' .. mission.deadline:sub(1, 4), x + 28 + nw, y + 90, 12, col.muted)

    -- streak badge
    local s = streak()
    local sc = s > 0 and col.orange or col.muted
    text(cr, '\u{F0238}', x + PW - 20, y + 74, 22, sc, { align = 'right' })
    text(cr, s .. ' day streak', x + PW - 20, y + 94, 11, sc, { align = 'right' })

    -- objectives
    local done = 0
    for _, it in ipairs(mission.items) do if it.done then done = done + 1 end end
    local total = math.max(#mission.items, 1)
    text(cr, 'objectives', x + 20, y + 126, 11, col.muted)
    text(cr, done .. '/' .. #mission.items, x + PW - 20, y + 126, 11, col.fg, { align = 'right', bold = true })
    U.bar(cr, x + 20, y + 134, PW - 40, 5, done / total * 100, col.cyan, col.purple)

    local next_marked = false
    for i = 1, math.min(6, #mission.items) do
        local it = mission.items[i]
        local ry = y + 164 + (i - 1) * 24
        if it.done then
            text(cr, '\u{F0135}', x + 20, ry, 14, col.green)
            text(cr, it.label, x + 42, ry - 1, 12, col.muted)
        else
            local first = not next_marked
            next_marked = true
            text(cr, first and '\u{F0142}' or '\u{F0131}', x + 20, ry, 14, first and col.cyan or col.muted)
            text(cr, it.label, x + 42, ry - 1, 12, first and col.fg or col.sub, { bold = first })
        end
    end

    -- commit heatmap: last 28 days, oldest left
    local hy = y + 322
    text(cr, 'lab commits · 28 days', x + 20, hy, 10, col.muted)
    local gap, ch = 4, 12
    local cw = (PW - 40 + gap) / 14
    for i = 0, 27 do
        local n = commits[day_key(27 - i)] or 0
        local cx = x + 20 + (i % 14) * cw
        local cy = hy + 10 + (i // 14) * (ch + gap)
        U.rrect(cr, cx, cy, cw - gap, ch, 3)
        if n == 0 then rgba(cr, col.track)
        else
            local a = math.min(1, 0.35 + n * 0.2)
            rgba(cr, i % 2 == 0 and col.cyan or col.purple, a)
        end
        cairo_fill(cr)
    end
end

local function draw_weather(cr)
    local x, y = WX, PY
    U.panel(cr, x, y, PW, PH)
    U.header(cr, x + 20, y + 30, PW, 'WEATHER', weather.city or 'Sydney')

    if weather.temp then
        local h = tonumber(os.date('%H'))
        local icon, ic = weather_icon(weather.code, h < 6 or h >= 19)
        text(cr, icon, x + 20, y + 100, 52, ic)
        local tw = text(cr, weather.temp .. '°', x + 96, y + 92, 44, col.fg, { bold = true })
        text(cr, weather.desc or '', x + 100 + tw, y + 74, 12, col.sub)
        text(cr, 'feels ' .. (weather.feels or '?') .. '°  ·  ' .. (weather.humidity or '?') .. '%', x + 100 + tw, y + 92, 11, col.muted)

        -- 3-day forecast
        local fw = (PW - 40 - 16) / 3
        for i = 0, 2 do
            local d = weather['day' .. i]
            if d then
                local date, hi, lo, code = d:match('([^|]+)|([^|]+)|([^|]+)|([^|]+)')
                local yy, mm, dd = date:match('(%d+)-(%d+)-(%d+)')
                local label = i == 0 and 'Today' or os.date('%a', os.time({ year = yy, month = mm, day = dd, hour = 12 }))
                local fx = x + 20 + i * (fw + 8)
                U.rrect(cr, fx, y + 116, fw, 52, 10)
                rgba(cr, col.tile)
                cairo_fill(cr)
                local fi, fc = weather_icon(code)
                text(cr, fi, fx + 10, y + 148, 18, fc)
                text(cr, label, fx + fw - 10, y + 136, 10, col.muted, { align = 'right' })
                text(cr, hi .. '° ' .. lo .. '°', fx + fw - 10, y + 155, 11, col.fg, { align = 'right' })
            end
        end
    else
        text(cr, 'fetching weather…', x + 20, y + 90, 12, col.muted)
    end

    -- calendar
    local cy = y + 200
    U.with_pattern(cr, U.grad(x + 20, 0, x + PW - 20, 0, col.cyan, col.purple, 0.3), function()
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, x + 20, cy - 12.5)
        cairo_line_to(cr, x + PW - 20, cy - 12.5)
        cairo_stroke(cr)
    end)
    text(cr, os.date('%B %Y'), x + 20, cy + 8, 13, col.fg, { bold = true })

    local cw = (PW - 40) / 7
    local names = { 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su' }
    for i, n in ipairs(names) do
        text(cr, n, x + 20 + (i - 0.5) * cw, cy + 34, 10, i >= 6 and col.purple or col.muted, { align = 'center', bold = true })
    end

    local now = os.date('*t')
    local first = os.date('*t', os.time({ year = now.year, month = now.month, day = 1, hour = 12 }))
    local offset = (first.wday + 5) % 7           -- Monday = 0
    local days = os.date('*t', os.time({ year = now.year, month = now.month + 1, day = 0, hour = 12 })).day
    for d = 1, days do
        local slot = offset + d - 1
        local cx = x + 20 + (slot % 7 + 0.5) * cw
        local ry = cy + 58 + (slot // 7) * 24
        if d == now.day then
            U.with_pattern(cr, U.grad(cx - 13, 0, cx + 13, 0, col.cyan, col.purple), function()
                U.rrect(cr, cx - 14, ry - 15, 28, 21, 7)
                cairo_fill(cr)
            end)
            text(cr, tostring(d), cx, ry, 12, col.black, { align = 'center', bold = true, alpha = 0.85 })
        else
            local past = d < now.day
            text(cr, tostring(d), cx, ry, 12, (slot % 7 >= 5) and col.purple or col.sub,
                { align = 'center', alpha = past and 0.45 or 1 })
        end
    end
end

---------------------------------------------------------------- entry

local tick = 0

function conky_main()
    if conky_window == nil then return end
    if tick % 30 == 0 then load_mission(); load_weather() end
    if tick % 300 == 0 then load_commits() end
    if tick % 1800 == 0 then fetch_weather() end
    tick = tick + 1

    local cs = U.surface()
    local cr = cairo_create(cs)
    draw_greeting(cr)
    draw_mission(cr)
    draw_weather(cr)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
