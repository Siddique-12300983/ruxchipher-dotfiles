-- ruxchipher WX: the big weather icon from the weather panel, animated.
-- It only animates for 6 seconds after a click, or for a few seconds every 10 minutes,
-- so most of the time it's a still image (cheap on battery).
local DIR = os.getenv('HOME') .. '/.config/conky/ruxchipher/'
local U = dofile(DIR .. 'common.lua')
local col, text, rgba, ICON = U.col, U.text, U.rgba, U.ICON

local BX, BY, SIZE = 10, 58, 52     -- glyph baseline, matches the old spot in the weather panel
local CX, CY = BX + 26, BY - 22     -- approximate glyph centre
local PERIOD, BURST = 600, 4        -- auto-play BURST seconds every PERIOD seconds

local code, night = nil, false
local play_until = 0      -- frame number a click-triggered animation runs until
local frame, anim_frame = 0, 0

local function load()
    local raw = U.readf(os.getenv('HOME') .. '/.cache/ruxchipher/weather.txt')
    local c = raw and raw:match('code=(%d+)')
    if c ~= code then code = c; anim_frame = 0 end   -- play once when the weather changes
    local h = tonumber(os.date('%H'))
    night = h < 6 or h >= 19
end

local function kind(icon)
    for k, v in pairs(ICON) do if v == icon then return k end end
    return 'cloud'
end

local function glyph(cr, g, c, dx, dy, alpha)
    text(cr, g, BX + (dx or 0), BY + (dy or 0), SIZE, c, { alpha = alpha })
end

local function drops(cr, t, n, c, len, speed, snow)
    for i = 1, n do
        local x = BX + 10 + (i - 1) * (36 / math.max(n - 1, 1))
        local phase = ((t * speed + i * 0.37) % 1)
        local y = BY - 6 + phase * 18
        rgba(cr, c, 0.9 * (1 - phase))
        if snow then
            cairo_new_path(cr)
            cairo_arc(cr, x + math.sin(t * 3 + i) * 2, y, 1.8, 0, 2 * math.pi)
            cairo_fill(cr)
        else
            cairo_set_line_width(cr, 2)
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
            cairo_move_to(cr, x, y)
            cairo_line_to(cr, x - 1.5, y + len)
            cairo_stroke(cr)
        end
    end
end

local function glow(cr, c, a)
    local g = cairo_pattern_create_radial(CX, CY, 0, CX, CY, 36)
    cairo_pattern_add_color_stop_rgba(g, 0, c[1], c[2], c[3], a)
    cairo_pattern_add_color_stop_rgba(g, 1, c[1], c[2], c[3], 0)
    U.with_pattern(cr, g, function() cairo_paint(cr) end)
end

local function animate(cr, icon, c, t)
    local k = kind(icon)
    if k == 'sun' then
        glow(cr, col.yellow, 0.18 + 0.10 * math.sin(t * 3))
        cairo_save(cr)
        cairo_translate(cr, CX, CY)
        cairo_rotate(cr, t * 0.8)
        cairo_translate(cr, -CX, -CY)
        glyph(cr, icon, c)
        cairo_restore(cr)
    elseif k == 'moon' then
        glow(cr, col.purple, 0.14 + 0.08 * math.sin(t * 2))
        glyph(cr, icon, c, 0, math.sin(t * 1.5) * 1.5)
    elseif k == 'partly' or k == 'cloud' then
        glyph(cr, icon, c, math.sin(t * 1.6) * 3, 0)
    elseif k == 'fog' then
        glyph(cr, icon, c, math.sin(t * 1.2) * 4, 0, 0.65 + 0.35 * math.sin(t * 2))
    elseif k == 'rain' or k == 'pour' then
        glyph(cr, ICON.cloud, c, math.sin(t * 1.4) * 1.5, -8)
        drops(cr, t, k == 'pour' and 7 or 5, col.cyan, k == 'pour' and 8 or 6, k == 'pour' and 2.2 or 1.6)
    elseif k == 'storm' then
        local flash = (frame % 23) < 2
        if flash then glow(cr, col.fg, 0.35) end
        glyph(cr, ICON.cloud, flash and col.fg or c, 0, -8)
        drops(cr, t, 5, col.blue, 7, 2.0)
        text(cr, '\u{F0E7}', CX - 6, BY + 8, 22, col.yellow, { alpha = flash and 1 or 0.35 })
    elseif k == 'snow' then
        glyph(cr, ICON.cloud, c, 0, -8)
        drops(cr, t, 5, col.fg, 0, 0.7, true)
    else
        glyph(cr, icon, c)
    end
end

function conky_wx()
    if conky_window == nil then return end
    if frame % 50 == 0 then load() end   -- every 5 s at 10 fps
    frame = frame + 1
    if not code then return end

    local icon, c = U.weather_icon(code, night)
    local burst = (os.time() % PERIOD) < BURST or anim_frame < BURST * 10
    local playing = frame < play_until or burst
    if playing then anim_frame = anim_frame + 1 end

    local cs = U.surface()
    local cr = cairo_create(cs)
    if playing then animate(cr, icon, c, anim_frame / 10) else glyph(cr, icon, c) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- GNOME only delivers clicks (not hover) to background X windows, so a click plays the animation.
function conky_wx_mouse(event)
    if event.type == 'button_down' then play_until = frame + 60 end
    return false
end
