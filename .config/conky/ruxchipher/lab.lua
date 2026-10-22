-- ruxchipher LAB: live status of the KVM lab, drawn with cairo.
require 'cairo'
pcall(require, 'cairo_xlib')

local W, H, PAD = 360, 156, 18
local FONT = 'JetBrainsMono Nerd Font'
local VIRSH = 'virsh -c qemu:///system '

local function hex(h, a)
    return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1 }
end

-- Tokyo Night (same palette as hud.lua)
local col = {
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
    red    = hex('#f7768e'),
}

local VMS = {
    { name = 'DC01',  role = 'domain ctrl', icon = '󰒋', accent = col.cyan },
    { name = 'WIN11', role = 'workstation', icon = '\u{F05B3}', accent = col.blue },
    { name = 'KALI',  role = 'attacker',    icon = '󰚌', accent = col.red },
}

---------------------------------------------------------------- data

local running, cpu, last_cpu, last_t = {}, {}, {}, nil
local net_up = false

-- One virsh call for every running VM's CPU time; % is the delta per vCPU.
local function poll()
    running = {}
    local now = os.time()
    local p = io.popen(VIRSH .. 'domstats --state-running --cpu-total --vcpu 2>/dev/null')
    local cur, stats = nil, {}
    if p then
        for line in p:lines() do
            local d = line:match("^Domain: '(.-)'")
            if d then cur = d; stats[d] = {}; running[d] = true end
            local k, v = line:match('^%s+([%w%.]+)=(%d+)')
            if cur and k then stats[cur][k] = tonumber(v) end
        end
        p:close()
    end
    for d, s in pairs(stats) do
        local t, n = s['cpu.time'], s['vcpu.current'] or 1
        if t and last_cpu[d] and last_t and now > last_t then
            cpu[d] = math.min(100, (t - last_cpu[d]) / ((now - last_t) * 1e9 * n) * 100)
        end
        last_cpu[d] = t
    end
    last_t = now

    local n = io.popen(VIRSH .. 'net-info lab 2>/dev/null')
    net_up = false
    if n then
        for line in n:lines() do
            if line:match('^Active:%s+yes') then net_up = true end
        end
        n:close()
    end
end

---------------------------------------------------------------- drawing

local ext = cairo_text_extents_t:create()

local function rgba(cr, c, a) cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4]) end

local function grad(x0, y0, x1, y1, c0, c1, a)
    local p = cairo_pattern_create_linear(x0, y0, x1, y1)
    cairo_pattern_add_color_stop_rgba(p, 0, c0[1], c0[2], c0[3], a or 1)
    cairo_pattern_add_color_stop_rgba(p, 1, c1[1], c1[2], c1[3], a or 1)
    return p
end

local function with_pattern(cr, p, fn)
    cairo_set_source(cr, p)
    fn()
    cairo_pattern_destroy(p)
end

local function text(cr, s, x, y, size, c, o)
    o = o or {}
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
        o.bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    cairo_text_extents(cr, s, ext)
    local tx = x
    if o.align == 'right' then tx = x - ext.x_advance
    elseif o.align == 'center' then tx = x - ext.x_advance / 2 end
    rgba(cr, c, o.alpha)
    cairo_move_to(cr, tx, y)
    cairo_show_text(cr, s)
    return ext.x_advance
end

local function rrect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 1.5 * math.pi)
    cairo_close_path(cr)
end

local function dot(cr, x, y, c, pulse)
    if pulse then
        rgba(cr, c, 0.18 + 0.12 * pulse)
        cairo_new_path(cr)
        cairo_arc(cr, x, y, 4 + 2 * pulse, 0, 2 * math.pi)
        cairo_fill(cr)
    end
    rgba(cr, c)
    cairo_new_path(cr)
    cairo_arc(cr, x, y, 3, 0, 2 * math.pi)
    cairo_fill(cr)
end

local function tile(cr, vm, x, y, w, h, pulse)
    local on = running[vm.name]

    rrect(cr, x + 0.5, y + 0.5, w - 1, h - 1, 12)
    rgba(cr, col.tile)
    cairo_fill_preserve(cr)
    cairo_set_line_width(cr, 1)
    if on then
        with_pattern(cr, grad(x, y, x + w, y + h, vm.accent, col.purple, 0.75), function() cairo_stroke(cr) end)
    else
        rgba(cr, col.track)
        cairo_stroke(cr)
    end

    -- soft accent glow in the top corner of running tiles
    if on then
        local g = cairo_pattern_create_radial(x + 18, y + 18, 0, x + 18, y + 18, 70)
        cairo_pattern_add_color_stop_rgba(g, 0, vm.accent[1], vm.accent[2], vm.accent[3], 0.16)
        cairo_pattern_add_color_stop_rgba(g, 1, vm.accent[1], vm.accent[2], vm.accent[3], 0)
        with_pattern(cr, g, function()
            rrect(cr, x + 1, y + 1, w - 2, h - 2, 11)
            cairo_fill(cr)
        end)
    end

    local a = on and 1 or 0.45
    text(cr, vm.icon, x + 12, y + 25, 16, vm.accent, { alpha = a })
    text(cr, vm.name, x + 34, y + 23, 13, col.fg, { bold = true, alpha = on and 1 or 0.6 })
    text(cr, vm.role, x + 12, y + 44, 10, col.muted)

    if on then
        dot(cr, x + 15, y + 59, col.green, pulse)
        text(cr, 'live', x + 26, y + 63, 10, col.green)
        local pct = cpu[vm.name] or 0
        text(cr, string.format('%d%%', math.floor(pct + 0.5)), x + w - 10, y + 63, 10, col.sub, { align = 'right' })
        rrect(cr, x + 12, y + h - 11, w - 24, 3, 1.5)
        rgba(cr, col.track)
        cairo_fill(cr)
        if pct > 0.5 then
            with_pattern(cr, grad(x + 12, 0, x + w - 12, 0, vm.accent, col.purple), function()
                rrect(cr, x + 12, y + h - 11, math.max(3, (w - 24) * pct / 100), 3, 1.5)
                cairo_fill(cr)
            end)
        end
    else
        dot(cr, x + 15, y + 59, col.muted)
        text(cr, 'offline', x + 24, y + 63, 10, col.muted)
    end
end

local function draw(cr, pulse)
    rrect(cr, 0.5, 0.5, W - 1, H - 1, 18)
    rgba(cr, col.bg)
    cairo_fill_preserve(cr)
    with_pattern(cr, grad(0, 0, W, H, col.cyan, col.purple, 0.45), function()
        cairo_set_line_width(cr, 1)
        cairo_stroke(cr)
    end)

    -- header
    local up = 0
    for _, vm in ipairs(VMS) do if running[vm.name] then up = up + 1 end end
    local x = PAD + text(cr, '◆ LAB', PAD, 28, 11, col.cyan, { bold = true })
    text(cr, '  harbourline freight', x, 28, 11, col.muted)

    local pill = string.format('%d/%d up', up, #VMS)
    local pc = up > 0 and col.green or col.muted
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 10)
    cairo_text_extents(cr, pill, ext)
    local pw = ext.x_advance + 16
    rrect(cr, W - PAD - pw, 15, pw, 18, 9)
    rgba(cr, pc, 0.12)
    cairo_fill_preserve(cr)
    rgba(cr, pc, 0.5)
    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)
    text(cr, pill, W - PAD - pw / 2, 28, 10, pc, { align = 'center', bold = true })

    -- tiles
    local gap = 12
    local tw = (W - 2 * PAD - 2 * gap) / 3
    for i, vm in ipairs(VMS) do
        tile(cr, vm, PAD + (i - 1) * (tw + gap), 42, tw, 84, pulse)
    end

    -- footer
    dot(cr, PAD + 3, 140, net_up and col.purple or col.muted)
    text(cr, 'net lab · ' .. (net_up and 'isolated · active' or 'down'), PAD + 12, 144, 10, col.muted)
    text(cr, 'kvm/qemu', W - PAD, 144, 10, col.muted, { align = 'right' })
end

---------------------------------------------------------------- entry

local tick = 0

function conky_main()
    if conky_window == nil then return end
    if tick % 3 == 0 then poll() end
    tick = tick + 1

    local pulse = (math.sin(tick * math.pi / 2) + 1) / 2
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    draw(cr, pulse)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
