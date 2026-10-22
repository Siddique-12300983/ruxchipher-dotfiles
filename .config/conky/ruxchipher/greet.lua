-- ruxchipher GREET: welcome card after login/unlock (~3 s), or the full-screen goodbye before
-- logout/shutdown: the screen dims, the card fades in, then everything fades to black (~3.5 s).
-- Status text comes from ~/.cache/ruxchipher/greet.txt, written by ~/.local/bin/ruxchipher-greet.
local DIR = os.getenv('HOME') .. '/.config/conky/ruxchipher/'
local U = dofile(DIR .. 'common.lua')
local col, text, rgba = U.col, U.text, U.rgba

local CW, CH = 640, 210                         -- card size

local info = {}
local raw = U.readf(os.getenv('HOME') .. '/.cache/ruxchipher/greet.txt') or ''
for k, v in raw:gmatch('(%w+)=([^\n]*)') do info[k] = v end
local bye = info.mode == 'bye'
local FPS = bye and 30 or 20

local function ease(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function greeting()
    if bye then return 'See you soon,' end
    if info.mode == 'unlock' then return 'Welcome back,' end
    local h = tonumber(os.date('%H'))
    return h < 5 and 'Burning the midnight oil,' or h < 12 and 'Good morning,'
        or h < 18 and 'Good afternoon,' or 'Good evening,'
end

local logo = nil

local function card(cr)
    U.panel(cr, 0, 0, CW, CH, 22)

    if not logo then logo = cairo_image_surface_create_from_png('/usr/share/ruxchipher/shield-128.png') end
    if cairo_surface_status(logo) == CAIRO_STATUS_SUCCESS then
        cairo_save(cr)
        cairo_translate(cr, 34, (CH - 112) / 2)
        cairo_scale(cr, 112 / 170, 112 / 170)
        cairo_set_source_surface(cr, logo, 0, 0)
        cairo_paint(cr)
        cairo_restore(cr)
    end

    local x = 168
    text(cr, greeting(), x, 74, 24, col.sub, { font = U.FONT_LIGHT })
    text(cr, 'Siddique.', x - 2, 130, 52, col.fg, { bold = true, pattern = U.grad(x, 0, x + 300, 0, col.cyan, col.purple) })

    local alerts = tonumber(info.alerts) or 0
    local ac = alerts > 0 and col.orange or col.green
    local tx = x
    tx = tx + text(cr, '\u{F0483} ', tx, 168, 13, ac)
    tx = tx + text(cr, alerts .. (info.mode == 'unlock' and ' alerts while you were away' or ' alerts today'), tx, 168, 12, ac)
    local lab = tonumber(info.lab) or 0
    tx = tx + text(cr, '   \u{F048B} lab ' .. lab .. '/3' .. ((bye and lab > 0) and ' still on' or ''), tx, 168, 12,
        (bye and lab > 0) and col.orange or col.sub)
    if bye then
        text(cr, '   study today ' .. (info.study or '0h 0m'), tx, 168, 12, col.muted)
    else
        text(cr, '   ' .. (info.days or '?') .. ' days to 2027', tx, 168, 12, col.muted)
    end
end

local frame = 0

function conky_greet()
    if conky_window == nil then return end
    frame = frame + 1
    local t = frame / FPS

    local cs = U.surface()
    local cr = cairo_create(cs)

    if bye then
        -- 0–0.6 s dim + card in · hold · 2.5–3.5 s everything fades to black
        local W, H = conky_window.width, conky_window.height
        local dim = 0.82 * ease(t / 0.6) + 0.18 * ease((t - 2.5) / 1.0)
        local a = ease(t / 0.6) * (1 - ease((t - 2.6) / 0.8))
        local s = 0.96 + 0.04 * ease(t / 0.6)

        cairo_set_source_rgba(cr, 0.02, 0.02, 0.04, dim)
        cairo_paint(cr)

        if a > 0.001 then
            cairo_push_group(cr)
            cairo_translate(cr, W / 2, H / 2 - 30 + (1 - ease(t / 0.6)) * 14)
            cairo_scale(cr, s, s)
            cairo_translate(cr, -CW / 2, -CH / 2)
            card(cr)
            cairo_pop_group_to_source(cr)
            cairo_paint_with_alpha(cr, a)
        end
    else
        local a = ease(t / 0.4) * (1 - ease((t - 2.6) / 0.4))
        cairo_push_group(cr)
        cairo_translate(cr, 0, (1 - ease(t / 0.4)) * 10)
        card(cr)
        cairo_pop_group_to_source(cr)
        cairo_paint_with_alpha(cr, a)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
