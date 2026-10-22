-- Shared drawing helpers and Tokyo Night palette for the left-side widgets.
require 'cairo'
pcall(require, 'cairo_xlib')

local M = {}

M.FONT = 'JetBrainsMono Nerd Font'
M.FONT_LIGHT = 'JetBrainsMono NF ExtraLight'

local function hex(h, a)
    return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1 }
end

M.col = {
    bg     = hex('#1a1b26', 0.86),
    tile   = hex('#24283b', 0.55),
    track  = hex('#292e42'),
    fg     = hex('#c0caf5'),
    sub    = hex('#a9b1d6'),
    muted  = hex('#565f89'),
    cyan   = hex('#7dcfff'),
    blue   = hex('#7aa2f7'),
    purple = hex('#bb9af7'),
    green  = hex('#9ece6a'),
    yellow = hex('#e0af68'),
    orange = hex('#ff9e64'),
    red    = hex('#f7768e'),
    black  = hex('#000000'),
}
local col = M.col

local ext = cairo_text_extents_t:create()

function M.readf(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

function M.lines(cmd)
    local out, p = {}, io.popen(cmd)
    if p then
        for l in p:lines() do out[#out + 1] = l end
        p:close()
    end
    return out
end

function M.rgba(cr, c, a) cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4]) end

function M.grad(x0, y0, x1, y1, c0, c1, a)
    local p = cairo_pattern_create_linear(x0, y0, x1, y1)
    cairo_pattern_add_color_stop_rgba(p, 0, c0[1], c0[2], c0[3], a or 1)
    cairo_pattern_add_color_stop_rgba(p, 1, c1[1], c1[2], c1[3], a or 1)
    return p
end

function M.with_pattern(cr, p, fn)
    cairo_set_source(cr, p)
    fn()
    cairo_pattern_destroy(p)
end

function M.measure(cr, s, size, o)
    o = o or {}
    cairo_select_font_face(cr, o.font or M.FONT, CAIRO_FONT_SLANT_NORMAL,
        o.bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    cairo_text_extents(cr, s, ext)
    return ext.x_advance
end

-- o: font, bold, align ('right'|'center'), alpha, shadow, pattern (cairo pattern, consumed)
function M.text(cr, s, x, y, size, c, o)
    o = o or {}
    local w = M.measure(cr, s, size, o)
    local tx = x
    if o.align == 'right' then tx = x - w
    elseif o.align == 'center' then tx = x - w / 2 end
    if o.shadow then
        M.rgba(cr, col.black, 0.55)
        cairo_move_to(cr, tx + 1, y + 2)
        cairo_show_text(cr, s)
    end
    if o.pattern then
        cairo_set_source(cr, o.pattern)
        cairo_pattern_destroy(o.pattern)
    else
        M.rgba(cr, c, o.alpha)
    end
    cairo_move_to(cr, tx, y)
    cairo_show_text(cr, s)
    return w
end

-- Greedy word wrap; returns the list of lines.
function M.wrap(cr, s, size, maxw, o)
    local out, line = {}, ''
    for word in s:gmatch('%S+') do
        local try = line == '' and word or (line .. ' ' .. word)
        if M.measure(cr, try, size, o) > maxw and line ~= '' then
            out[#out + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= '' then out[#out + 1] = line end
    return out
end

function M.rrect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 1.5 * math.pi)
    cairo_close_path(cr)
end

-- Panel with the same gradient border and corner glow as the HUD.
function M.panel(cr, x, y, w, h, r)
    r = r or 18
    M.rrect(cr, x + 0.5, y + 0.5, w - 1, h - 1, r)
    M.rgba(cr, col.bg)
    cairo_fill_preserve(cr)
    M.with_pattern(cr, M.grad(x, y, x + w, y + h, col.cyan, col.purple, 0.45), function()
        cairo_set_line_width(cr, 1)
        cairo_stroke(cr)
    end)
    local g = cairo_pattern_create_radial(x + 40, y + 40, 0, x + 40, y + 40, 240)
    cairo_pattern_add_color_stop_rgba(g, 0, col.cyan[1], col.cyan[2], col.cyan[3], 0.07)
    cairo_pattern_add_color_stop_rgba(g, 1, col.cyan[1], col.cyan[2], col.cyan[3], 0)
    M.with_pattern(cr, g, function()
        M.rrect(cr, x + 1, y + 1, w - 2, h - 2, r - 1)
        cairo_fill(cr)
    end)
end

function M.header(cr, x, y, w, title, sub)
    local tw = M.text(cr, '◆ ' .. title, x, y, 11, col.cyan, { bold = true })
    if sub then M.text(cr, '  ' .. sub, x + tw, y, 11, col.muted) end
end

function M.bar(cr, x, y, w, h, pct, c0, c1)
    M.rgba(cr, col.track)
    M.rrect(cr, x, y, w, h, h / 2)
    cairo_fill(cr)
    if pct > 0 then
        M.with_pattern(cr, M.grad(x, 0, x + w, 0, c0, c1), function()
            M.rrect(cr, x, y, math.max(h, w * math.min(pct, 100) / 100), h, h / 2)
            cairo_fill(cr)
        end)
    end
end

function M.surface()
    return cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
end

-- wttr.in weather code -> Nerd Font icon + colour (shared by left.lua and wx.lua)
M.ICON = {
    sun = '\u{F0599}', moon = '\u{F0594}', partly = '\u{F0595}', cloud = '\u{F0590}',
    fog = '\u{F0591}', rain = '\u{F0597}', pour = '\u{F0596}', storm = '\u{F0593}', snow = '\u{F0598}',
}

function M.weather_icon(code, night)
    code = tonumber(code) or 0
    if code == 113 then return night and M.ICON.moon or M.ICON.sun, col.yellow end
    if code == 116 then return M.ICON.partly, col.sub end
    if code == 119 or code == 122 then return M.ICON.cloud, col.sub end
    if code == 143 or code == 248 or code == 260 then return M.ICON.fog, col.muted end
    if code == 200 or (code >= 386 and code <= 395) then return M.ICON.storm, col.purple end
    if (code >= 179 and code <= 230) or (code >= 320 and code <= 377 and code ~= 353 and code ~= 356 and code ~= 359) then
        return M.ICON.snow, col.fg
    end
    if code == 305 or code == 308 or code == 356 or code == 359 then return M.ICON.pour, col.blue end
    return M.ICON.rain, col.cyan
end

return M
