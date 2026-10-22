-- ruxchipher MEDIA: now playing (any MPRIS player: Spotify, browsers, mpv...).
local DIR = os.getenv('HOME') .. '/.config/conky/ruxchipher/'
local U = dofile(DIR .. 'common.lua')
local col, text, rgba = U.col, U.text, U.rgba

local W, H, PAD = 360, 156, 18
local ART = 96
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

local function draw_art(cr, x, y, playing)
    U.rrect(cr, x, y, ART, ART, 12)
    if art_surface then
        cairo_save(cr)
        cairo_clip_preserve(cr)
        cairo_translate(cr, x, y)
        cairo_scale(cr, 0.5, 0.5)
        cairo_set_source_surface(cr, art_surface, 0, 0)
        cairo_paint(cr)
        cairo_restore(cr)
        cairo_new_path(cr)
    else
        U.with_pattern(cr, U.grad(x, y, x + ART, y + ART, col.cyan, col.purple, playing and 0.35 or 0.15), function()
            cairo_fill(cr)
        end)
        text(cr, '\u{F075A}', x + ART / 2, y + ART / 2 + 14, 38, col.fg, { align = 'center', alpha = 0.8 })
    end
    U.rrect(cr, x + 0.5, y + 0.5, ART - 1, ART - 1, 12)
    rgba(cr, col.fg, 0.12)
    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)
end

-- small animated equaliser next to the status while playing
local function eq(cr, x, y, t, on)
    for i = 0, 3 do
        local h = on and (4 + 8 * math.abs(math.sin(t * 1.7 + i * 1.3))) or 3
        U.rrect(cr, x + i * 5, y - h, 3, h, 1.5)
        rgba(cr, i % 2 == 0 and col.cyan or col.purple)
        cairo_fill(cr)
    end
end

local tick = 0

local function draw(cr)
    U.panel(cr, 0, 0, W, H)
    local playing = now.status == 'Playing'
    local ax, ay = PAD, (H - ART) / 2
    draw_art(cr, ax, ay, playing)

    local tx, tw = ax + ART + 16, W - PAD - (ax + ART + 16)

    local hdr = playing and col.green or col.muted
    eq(cr, tx, ay + 16, tick, playing)
    text(cr, (playing and 'PLAYING' or 'PAUSED') .. '  ·  ' .. (now.player or ''), tx + 26, ay + 16, 10, hdr, { bold = true })

    text(cr, fit(cr, now.title ~= '' and now.title or 'Unknown title', 14, tw, { bold = true }), tx, ay + 44, 14, col.fg, { bold = true })
    text(cr, fit(cr, now.artist ~= '' and now.artist or '—', 12, tw), tx, ay + 64, 12, col.sub)

    local pct = now.len > 0 and math.min(100, now.pos / now.len * 100) or 0
    U.bar(cr, tx, ay + 78, tw, 4, pct, col.cyan, col.purple)
    if now.len > 0 then
        local kx = tx + tw * pct / 100
        rgba(cr, col.fg)
        cairo_new_path(cr)
        cairo_arc(cr, kx, ay + 80, 4, 0, 2 * math.pi)
        cairo_fill(cr)
    end
    text(cr, clock(now.pos), tx, ay + 98, 10, col.muted)
    text(cr, now.len > 0 and clock(now.len) or 'live', tx + tw, ay + 98, 10, col.muted, { align = 'right' })
end

-- 0 = hidden, 1 = fully shown; eases toward the target so the widget fades in/out.
local vis = 0
local shown = {}   -- last track drawn, kept so the fade-out still has content

function conky_main()
    if conky_window == nil then return end
    poll()
    local active = now.status == 'Playing' or now.status == 'Paused'
    if active then
        update_art()
        shown = now
    end
    vis = math.max(0, math.min(1, vis + (active and 0.34 or -0.34)))
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
