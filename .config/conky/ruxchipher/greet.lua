-- ruxchipher GREET: a short welcome card shown after login or unlock (~3 s, then conky exits).
-- Status text comes from ~/.cache/ruxchipher/greet.txt, written by ~/.local/bin/ruxchipher-greet.
local DIR = os.getenv('HOME') .. '/.config/conky/ruxchipher/'
local U = dofile(DIR .. 'common.lua')
local col, text, rgba = U.col, U.text, U.rgba

local W, H = 640, 210
local FRAMES, FADE = 60, 8          -- at 20 fps: 3 s total, 0.4 s fades

local info = {}
local raw = U.readf(os.getenv('HOME') .. '/.cache/ruxchipher/greet.txt') or ''
for k, v in raw:gmatch('(%w+)=([^\n]*)') do info[k] = v end

local function greeting()
    local h = tonumber(os.date('%H'))
    local hi = h < 5 and 'Burning the midnight oil,' or h < 12 and 'Good morning,'
        or h < 18 and 'Good afternoon,' or 'Good evening,'
    return info.mode == 'unlock' and 'Welcome back,' or hi
end

local frame = 0

function conky_greet()
    if conky_window == nil then return end
    frame = frame + 1
    local a = 1
    if frame < FADE then a = frame / FADE end
    if frame > FRAMES - FADE then a = math.max(0, (FRAMES - frame) / FADE) end
    local rise = (1 - math.min(1, frame / FADE)) * 10      -- slides up slightly while fading in

    local cs = U.surface()
    local cr = cairo_create(cs)
    cairo_push_group(cr)
    cairo_translate(cr, 0, rise)

    U.panel(cr, 0, 0, W, H, 22)

    local logo = cairo_image_surface_create_from_png('/usr/share/ruxchipher/shield-128.png')
    if cairo_surface_status(logo) == CAIRO_STATUS_SUCCESS then
        cairo_save(cr)
        cairo_translate(cr, 34, (H - 112) / 2)
        cairo_scale(cr, 112 / 170, 112 / 170)
        cairo_set_source_surface(cr, logo, 0, 0)
        cairo_paint(cr)
        cairo_restore(cr)
    end
    cairo_surface_destroy(logo)

    local x = 168
    text(cr, greeting(), x, 74, 24, col.sub, { font = U.FONT_LIGHT })
    text(cr, 'Siddique.', x - 2, 130, 52, col.fg, { bold = true, pattern = U.grad(x, 0, x + 300, 0, col.cyan, col.purple) })

    local alerts = tonumber(info.alerts) or 0
    local ac = alerts > 0 and col.orange or col.green
    local tx = x
    tx = tx + text(cr, '\u{F0483} ', tx, 168, 13, ac)
    tx = tx + text(cr, alerts .. (info.mode == 'unlock' and ' alerts while you were away' or ' alerts today'), tx, 168, 12, ac)
    tx = tx + text(cr, '   \u{F048B} lab ' .. (info.lab or '0') .. '/3', tx, 168, 12, col.sub)
    text(cr, '   ' .. (info.days or '?') .. ' days to 2027', tx, 168, 12, col.muted)

    cairo_pop_group_to_source(cr)
    cairo_paint_with_alpha(cr, a)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
