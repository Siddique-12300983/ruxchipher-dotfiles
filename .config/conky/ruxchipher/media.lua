-- ruxchipher MEDIA: now playing (any MPRIS player: Spotify, browsers, mpv...), top centre.
-- No panel: feathered album art, light text and a fading progress line, so it reads as part of
-- the wallpaper. Fades in while something is playing or paused, out when the player goes away.
local DIR = os.getenv('HOME') .. '/.config/conky/ruxchipher/'
local U = dofile(DIR .. 'common.lua')
local col, text, rgba = U.col, U.text, U.rgba

local W, H = 760, 180
local TITLE_FONT = 'Space Grotesk Light Light'    -- big track title (Space Grotesk 300)
local BODY_FONT = 'Space Grotesk Light Medium'    -- artist, label and times (Space Grotesk 500)
local ART = 140
local CACHE = os.getenv('HOME') .. '/.cache/ruxchipher/'

local FMT = '{{status}}\t{{artist}}\t{{title}}\t{{position}}\t{{mpris:length}}\t{{mpris:artUrl}}\t{{playerName}}'

local now = {}
local art_url, art_surface = nil, nil
local art_file = CACHE .. 'art.png'

local function poll()
    local line = U.lines("playerctl metadata --format '" .. FMT .. "' 2>/dev/null")[1]
    now = {}
    if not line then return end
    local f = {}
    for v in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = v end
    now = {
        status = f[1], artist = f[2], title = f[3],
        pos = (tonumber(f[4]) or 0) / 1e6, len = (tonumber(f[5]) or 0) / 1e6,
        art = f[6], player = f[7],
    }
end

-- Album art arrives as file:// or https://; art.sh turns it into a square PNG in the background.
local function update_art()
    local url = now.art
    if url == art_url then
        if not art_surface and url and url ~= '' then
            local f = io.open(art_file, 'r')
            if f then
                f:close()
                art_surface = cairo_image_surface_create_from_png(art_file)
            end
        end
        return
    end
    art_url = url
    if art_surface then cairo_surface_destroy(art_surface); art_surface = nil end
    os.remove(art_file)
    if not url or url == '' then return end
    local q = function(v) return "'" .. v:gsub("'", "'\\''") .. "'" end
    os.execute('mkdir -p ' .. q(CACHE) .. '; ' .. q(DIR .. 'art.sh') .. ' ' .. q(url) .. ' ' .. q(art_file) .. ' >/dev/null 2>&1 &')
end

local function clock(s)
    s = math.floor(s)
    return string.format('%d:%02d', s // 60, s % 60)
end

local function fit(cr, s, size, maxw, o)
    if U.measure(cr, s, size, o) <= maxw then return s end
    while #s > 1 and U.measure(cr, s .. '…', size, o) > maxw do
        s = s:sub(1, -2)
        while #s > 0 and s:byte(-1) >= 0x80 and s:byte(-1) < 0xC0 do s = s:sub(1, -2) end  -- utf-8 safe
        if #s > 0 and s:byte(-1) >= 0xC0 then s = s:sub(1, -2) end
    end
    return s .. '…'
end

-- Album art fading out at the edges (radial mask), with a soft colour glow behind it.
local function draw_art(cr, x, y, playing)
    local cx, cy = x + ART / 2, y + ART / 2
    local glow = cairo_pattern_create_radial(cx, cy, 0, cx, cy, ART * 0.85)
    cairo_pattern_add_color_stop_rgba(glow, 0, col.purple[1], col.purple[2], col.purple[3], playing and 0.22 or 0.1)
    cairo_pattern_add_color_stop_rgba(glow, 1, col.cyan[1], col.cyan[2], col.cyan[3], 0)
    U.with_pattern(cr, glow, function()
        cairo_rectangle(cr, cx - ART, cy - ART, ART * 2, ART * 2)
        cairo_fill(cr)
    end)

    if art_surface then
        -- draw in the art's own pixel space so the source survives; the mask is built in that space too
        local px = cairo_image_surface_get_width(art_surface)
        local k = ART / px
        cairo_save(cr)
        cairo_translate(cr, x, y)
        cairo_scale(cr, k, k)
        cairo_set_source_surface(cr, art_surface, 0, 0)
        local mask = cairo_pattern_create_radial(px / 2, px / 2, px * 0.20, px / 2, px / 2, px * 0.49)
        cairo_pattern_add_color_stop_rgba(mask, 0, 0, 0, 0, 1)
        cairo_pattern_add_color_stop_rgba(mask, 1, 0, 0, 0, 0)
        cairo_mask(cr, mask)
        cairo_pattern_destroy(mask)
        cairo_restore(cr)
    else
        text(cr, '\u{F075A}', cx, cy + 22, 64, col.purple, { align = 'center', alpha = 0.55 })
    end
end

-- tiny equaliser next to the label while playing
local function eq(cr, x, y, t, on)
    for i = 0, 3 do
        local h = on and (3 + 7 * math.abs(math.sin(t * 0.9 + i * 1.3))) or 2
        U.rrect(cr, x + i * 4, y - h, 2.5, h, 1.2)
        rgba(cr, i % 2 == 0 and col.cyan or col.purple, 0.7)
        cairo_fill(cr)
    end
end

local tick = 0

local function draw(cr)
    local playing = now.status == 'Playing'
    local TW = 520
    local x0 = (W - (ART + 28 + TW)) / 2
    draw_art(cr, x0, (H - ART) / 2, playing)

    local tx = x0 + ART + 28
    eq(cr, tx, 46, tick, playing)
    text(cr, (playing and 'now playing' or 'paused') .. '  ·  ' .. (now.player or ''), tx + 22, 46, 11,
        playing and col.cyan or col.muted, { font = BODY_FONT, alpha = 0.8, shadow = true })

    text(cr, fit(cr, now.title ~= '' and now.title or 'Unknown title', 34, TW, { font = TITLE_FONT }), tx, 92, 34, col.fg,
        { font = TITLE_FONT, alpha = 0.95, shadow = true })
    text(cr, fit(cr, now.artist ~= '' and now.artist or '—', 15, TW, { font = BODY_FONT }), tx, 120, 15, col.sub,
        { font = BODY_FONT, alpha = 0.85, shadow = true })

    -- progress: a faint line fading out at both ends, and a "comet" fill that brightens toward the playhead
    local ly = 140.5
    local track = cairo_pattern_create_linear(tx, 0, tx + TW, 0)
    cairo_pattern_add_color_stop_rgba(track, 0, col.fg[1], col.fg[2], col.fg[3], 0)
    cairo_pattern_add_color_stop_rgba(track, 0.15, col.fg[1], col.fg[2], col.fg[3], 0.18)
    cairo_pattern_add_color_stop_rgba(track, 0.85, col.fg[1], col.fg[2], col.fg[3], 0.18)
    cairo_pattern_add_color_stop_rgba(track, 1, col.fg[1], col.fg[2], col.fg[3], 0)
    cairo_set_line_width(cr, 1.5)
    U.with_pattern(cr, track, function()
        cairo_move_to(cr, tx, ly)
        cairo_line_to(cr, tx + TW, ly)
        cairo_stroke(cr)
    end)

    if now.len > 0 then
        local kx = tx + TW * math.min(1, now.pos / now.len)
        if kx > tx + 2 then
            local fill = cairo_pattern_create_linear(tx, 0, kx, 0)
            cairo_pattern_add_color_stop_rgba(fill, 0, col.cyan[1], col.cyan[2], col.cyan[3], 0)
            cairo_pattern_add_color_stop_rgba(fill, 1, col.purple[1], col.purple[2], col.purple[3], 0.95)
            cairo_set_line_width(cr, 2)
            U.with_pattern(cr, fill, function()
                cairo_move_to(cr, tx, ly)
                cairo_line_to(cr, kx, ly)
                cairo_stroke(cr)
            end)
        end
        local g = cairo_pattern_create_radial(kx, ly, 0, kx, ly, 12)
        cairo_pattern_add_color_stop_rgba(g, 0, col.purple[1], col.purple[2], col.purple[3], 0.55)
        cairo_pattern_add_color_stop_rgba(g, 1, col.purple[1], col.purple[2], col.purple[3], 0)
        U.with_pattern(cr, g, function()
            cairo_arc(cr, kx, ly, 12, 0, 2 * math.pi)
            cairo_fill(cr)
        end)
        rgba(cr, col.fg, 0.95)
        cairo_new_path(cr)
        cairo_arc(cr, kx, ly, 3, 0, 2 * math.pi)
        cairo_fill(cr)
    end
    text(cr, clock(now.pos), tx, 162, 11, col.muted, { font = BODY_FONT, alpha = 0.8, shadow = true })
    text(cr, now.len > 0 and clock(now.len) or 'live', tx + TW, 162, 11, col.muted, { font = BODY_FONT, align = 'right', alpha = 0.8, shadow = true })
end

-- 0 = hidden, 1 = fully shown; eases toward the target so the widget fades in/out.
local vis = 0
local shown = {}   -- last track drawn, kept so the fade-out still has content

local active = false

function conky_main()
    if conky_window == nil then return end
    -- at 5 fps: ask the player every 2nd frame while visible, every 5th while hidden (saves battery)
    if tick % ((vis > 0 or active) and 2 or 5) == 0 then
        poll()
        active = now.status == 'Playing' or now.status == 'Paused'
        if active then
            update_art()
            shown = now
        end
    end
    vis = math.max(0, math.min(1, vis + (active and 0.12 or -0.12)))   -- ~1.7 s fade
    tick = tick + 1
    if vis == 0 then return end

    local cs = U.surface()
    local cr = cairo_create(cs)
    local live = now
    now = shown
    cairo_push_group(cr)
    draw(cr)
    cairo_pop_group_to_source(cr)
    cairo_paint_with_alpha(cr, vis)
    now = live
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
