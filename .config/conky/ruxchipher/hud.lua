-- ruxchipher HUD: draws the whole widget with cairo.
require 'cairo'
pcall(require, 'cairo_xlib')

local W, H, PAD = 360, 800, 24
local FONT = 'JetBrainsMono Nerd Font'
local FONT_LIGHT = 'JetBrainsMono NF ExtraLight'

local function hex(h, a)
    return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1 }
end

-- Tokyo Night
local col = {
    bg     = hex('#1a1b26', 0.86),
    track  = hex('#292e42'),
    fg     = hex('#c0caf5'),
    sub    = hex('#a9b1d6'),
    muted  = hex('#565f89'),
    cyan   = hex('#7dcfff'),
    blue   = hex('#7aa2f7'),
    purple = hex('#bb9af7'),
    green  = hex('#9ece6a'),
    orange = hex('#ff9e64'),
    red    = hex('#f7768e'),
}

---------------------------------------------------------------- data

local function readf(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('*l')
    f:close()
    return s
end

local function sh(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local s = p:read('*l')
    p:close()
    return s
end

local hwmon = {}      -- hwmon name -> sysfs dir (numbers change between boots)
local gpu_dev = nil
local gpu = { state = 'sleep', util = 0, temp = nil }
local iface = 'wlan0'
local hist_down, hist_up, N = {}, {}, 60

local function init()
    local p = io.popen('for d in /sys/class/hwmon/hwmon*; do echo "$d $(cat $d/name)"; done')
    if p then
        for line in p:lines() do
            local d, n = line:match('^(%S+)%s+(%S+)$')
            if d and not hwmon[n] then hwmon[n] = d end
        end
        p:close()
    end
    gpu_dev = sh('for d in /sys/bus/pci/devices/*; do [ "$(cat $d/vendor)" = 0x10de ] && case $(cat $d/class) in 0x03*) echo $d;; esac; done | head -n1')
end

local function hw_value(name, file, div)
    if not hwmon[name] then return nil end
    local v = tonumber(readf(hwmon[name] .. '/' .. file))
    return v and v / (div or 1)
end

-- Only ask nvidia-smi when the GPU is already awake, so the widget never
-- wakes the dGPU and drains the battery.
local function poll_gpu()
    gpu.state, gpu.util, gpu.temp = 'sleep', 0, nil
    if not gpu_dev or readf(gpu_dev .. '/power/runtime_status') ~= 'active' then return end
    local out = sh('nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null')
    local u, t = (out or ''):match('(%d+)%s*,%s*(%d+)')
    if u then gpu.state, gpu.util, gpu.temp = 'on', tonumber(u), tonumber(t) end
end

local function pick_iface()
    local dev = sh('ip route show default 2>/dev/null | head -n1')
    dev = dev and dev:match('dev%s+(%S+)')
    if dev then iface = dev end
end

local function push(t, v)
    t[#t + 1] = v
    if #t > N then table.remove(t, 1) end
end

local function num(s) return tonumber(conky_parse(s)) or 0 end

local function fmt_speed(kib)
    if kib >= 1024 then return string.format('%.1f MB/s', kib / 1024) end
    return string.format('%.0f KB/s', kib)
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
    cairo_select_font_face(cr, o.font or FONT, CAIRO_FONT_SLANT_NORMAL,
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

local function section(cr, title, y, right)
    local w = text(cr, title, PAD, y, 10, col.muted, { bold = true })
    local x1 = W - PAD
    if right then x1 = x1 - text(cr, right, W - PAD, y, 11, col.sub, { align = 'right' }) - 10 end
    with_pattern(cr, grad(PAD + w + 10, 0, x1, 0, col.blue, col.blue, 0.18), function()
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, PAD + w + 10, y - 4)
        cairo_line_to(cr, x1, y - 4)
        cairo_stroke(cr)
    end)
end

local function bar(cr, x, y, w, h, pct, c0, c1)
    rgba(cr, col.track)
    rrect(cr, x, y, w, h, h / 2)
    cairo_fill(cr)
    if pct > 0 then
        local pw = math.max(h, w * math.min(pct, 100) / 100)
        with_pattern(cr, grad(x, 0, x + w, 0, c0, c1), function()
            rrect(cr, x, y, pw, h, h / 2)
            cairo_fill(cr)
        end)
    end
end

-- 270° gauge with a soft glow; turns red when the value is high.
local function ring(cr, cx, cy, r, pct, label, subtext)
    pct = math.max(0, math.min(100, pct))
    local s, sweep, lw = 0.75 * math.pi, 1.5 * math.pi, 7
    local hot = pct >= 85 and col.red or col.purple

    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, lw)
    rgba(cr, col.track)
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r, s, s + sweep)
    cairo_stroke(cr)

    if pct > 0.5 then
        local e = s + sweep * pct / 100
        with_pattern(cr, grad(cx - r, cy + r, cx + r, cy - r, col.cyan, hot, 0.14), function()
            cairo_set_line_width(cr, lw + 9)
            cairo_new_path(cr)
            cairo_arc(cr, cx, cy, r, s, e)
            cairo_stroke(cr)
        end)
        with_pattern(cr, grad(cx - r, cy + r, cx + r, cy - r, col.cyan, hot), function()
            cairo_set_line_width(cr, lw)
            cairo_new_path(cr)
            cairo_arc(cr, cx, cy, r, s, e)
            cairo_stroke(cr)
        end)
    end

    text(cr, string.format('%d%%', math.floor(pct + 0.5)), cx, cy + 6, 18, col.fg, { align = 'center', bold = true })
    text(cr, label, cx, cy + r - 2, 10, col.muted, { align = 'center', bold = true })
    text(cr, subtext, cx, cy + r + 22, 11, col.sub, { align = 'center' })
end

local function graph(cr, x, y, w, h)
    local max = 128
    for i = 1, #hist_down do max = math.max(max, hist_down[i], hist_up[i] or 0) end

    rgba(cr, col.muted, 0.22)
    cairo_set_line_width(cr, 1)
    cairo_set_dash(cr, { 2, 4 }, 2, 0)
    for i = 0, 2 do
        cairo_move_to(cr, x, y + i * h / 2 + 0.5)
        cairo_line_to(cr, x + w, y + i * h / 2 + 0.5)
    end
    cairo_stroke(cr)
    cairo_set_dash(cr, {}, 0, 0)

    local step = w / (N - 1)
    local function trace(t)
        local off = N - #t
        cairo_move_to(cr, x + off * step, y + h)
        for i = 1, #t do
            cairo_line_to(cr, x + (off + i - 1) * step, y + h - (t[i] / max) * (h - 4))
        end
    end
    local function series(t, c, fill_a)
        if #t < 2 then return end
        trace(t)
        cairo_line_to(cr, x + w, y + h)
        cairo_close_path(cr)
        local p = cairo_pattern_create_linear(0, y, 0, y + h)
        cairo_pattern_add_color_stop_rgba(p, 0, c[1], c[2], c[3], fill_a)
        cairo_pattern_add_color_stop_rgba(p, 1, c[1], c[2], c[3], 0)
        with_pattern(cr, p, function() cairo_fill(cr) end)
        trace(t)
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
        cairo_set_line_width(cr, 1.6)
        rgba(cr, c)
        cairo_stroke(cr)
    end
    series(hist_down, col.cyan, 0.38)
    series(hist_up, col.purple, 0.22)
end

local function draw(cr)
    -- panel
    rrect(cr, 0.5, 0.5, W - 1, H - 1, 20)
    rgba(cr, col.bg)
    cairo_fill_preserve(cr)
    with_pattern(cr, grad(0, 0, W, H, col.cyan, col.purple, 0.45), function()
        cairo_set_line_width(cr, 1)
        cairo_stroke(cr)
    end)
    local glow = cairo_pattern_create_radial(40, 40, 0, 40, 40, 260)
    cairo_pattern_add_color_stop_rgba(glow, 0, col.cyan[1], col.cyan[2], col.cyan[3], 0.08)
    cairo_pattern_add_color_stop_rgba(glow, 1, col.cyan[1], col.cyan[2], col.cyan[3], 0)
    with_pattern(cr, glow, function()
        rrect(cr, 1, 1, W - 2, H - 2, 20)
        cairo_fill(cr)
    end)

    -- header
    rgba(cr, col.green)
    cairo_arc(cr, PAD + 4, 38, 4, 0, 2 * math.pi)
    cairo_fill(cr)
    text(cr, 'ruxchipher@arch', PAD + 16, 42, 12, col.sub)
    text(cr, 'up ' .. conky_parse('${uptime_short}'), W - PAD, 42, 11, col.muted, { align = 'right' })

    -- clock
    local cw = text(cr, os.date('%H:%M'), PAD - 3, 118, 66, col.fg, { font = FONT_LIGHT })
    text(cr, os.date(':%S'), PAD + cw + 2, 118, 20, col.purple)
    text(cr, os.date('%A, %d %B'), PAD, 146, 13, col.sub)

    with_pattern(cr, grad(PAD, 0, W - PAD, 0, col.cyan, col.purple, 0.35), function()
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, PAD, 172.5)
        cairo_line_to(cr, W - PAD, 172.5)
        cairo_stroke(cr)
    end)

    -- gauges
    local cpu_t = hw_value('k10temp', 'temp1_input', 1000)
    ring(cr, 66, 238, 38, num('${cpu cpu0}'), 'CPU', cpu_t and string.format('%.0f°C', cpu_t) or '--')
    ring(cr, W / 2, 238, 38, num('${memperc}'), 'RAM', conky_parse('${mem}'))
    ring(cr, W - 66, 238, 38, gpu.util, 'GPU', gpu.temp and string.format('%d°C', gpu.temp) or 'asleep')

    -- network
    local down, up = num('${downspeedf ' .. iface .. '}'), num('${upspeedf ' .. iface .. '}')
    push(hist_down, down)
    push(hist_up, up)
    local ssid = conky_parse('${wireless_essid ' .. iface .. '}')
    if ssid == '' or ssid == 'off/any' then ssid = iface end
    section(cr, 'NETWORK', 338, ssid)
    graph(cr, PAD, 354, W - 2 * PAD, 64)
    text(cr, '↓ ' .. fmt_speed(down), PAD, 440, 12, col.cyan)
    text(cr, '↑ ' .. fmt_speed(up), W - PAD, 440, 12, col.purple, { align = 'right' })
    text(cr, 'ip ' .. conky_parse('${addr ' .. iface .. '}'), PAD, 460, 11, col.muted)

    -- storage
    local fs = num('${fs_used_perc /}')
    section(cr, 'STORAGE', 498)
    bar(cr, PAD, 512, W - 2 * PAD, 6, fs, col.blue, fs >= 90 and col.red or col.purple)
    local nvme_t = hw_value('nvme', 'temp1_input', 1000)
    text(cr, conky_parse('${fs_used /}') .. ' / ' .. conky_parse('${fs_size /}') ..
        (nvme_t and string.format('  ·  %.0f°C', nvme_t) or ''), PAD, 538, 12, col.sub)
    text(cr, string.format('%d%%', fs), W - PAD, 538, 12, col.fg, { align = 'right', bold = true })

    -- power
    local bat = tonumber(readf('/sys/class/power_supply/BAT1/capacity')) or 0
    local status = readf('/sys/class/power_supply/BAT1/status') or 'Unknown'
    section(cr, 'POWER', 578)
    bar(cr, PAD, 592, W - 2 * PAD, 6, bat, bat <= 20 and col.red or col.green, bat <= 20 and col.orange or col.cyan)
    text(cr, string.format('%d%%  ·  %s', bat, status), PAD, 618, 12, col.sub)
    local f1, f2 = hw_value('asus', 'fan1_input'), hw_value('asus', 'fan2_input')
    if f1 then
        text(cr, string.format('fan %d · %d rpm', f1, f2 or 0), W - PAD, 618, 11, col.muted, { align = 'right' })
    end

    -- processes
    section(cr, 'TOP PROCESSES', 658)
    for i = 1, 4 do
        local y = 662 + i * 22
        local name = (conky_parse('${top name ' .. i .. '}') or ''):gsub('^%s+', ''):gsub('%s+$', '')
        local pct = num('${top cpu ' .. i .. '}')
        if #name > 18 then name = name:sub(1, 17) .. '…' end
        text(cr, name, PAD, y, 12, i == 1 and col.fg or col.sub)
        bar(cr, W - PAD - 118, y - 6, 64, 3, math.min(pct * 2, 100), col.cyan, col.purple)
        text(cr, string.format('%.1f%%', pct), W - PAD, y, 12, col.fg, { align = 'right' })
    end

    text(cr, 'linux ' .. conky_parse('${kernel}'), W / 2, H - 20, 10, col.muted, { align = 'center' })
end

---------------------------------------------------------------- entry

local tick = 0

function conky_main()
    if conky_window == nil then return end
    if (tonumber(conky_parse('${updates}')) or 0) < 2 then return end

    if tick == 0 then init() end
    if tick % 15 == 0 then poll_gpu() end
    if tick % 10 == 0 then pick_iface() end
    tick = tick + 1

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    draw(cr)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
