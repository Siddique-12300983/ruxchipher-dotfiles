# ruxchipher dotfiles

My Arch Linux workstation (GNOME on Wayland), customised into a security-aware desktop in Tokyo Night colours.
Part of my path to a purple team internship. See the portfolio at **[ruxchipher.com](https://ruxchipher.com)**.

| Main HUD | Left panels |
|---|---|
| ![HUD](screenshots/hud.png) | ![Greeting, mission tracker, weather and calendar](screenshots/left-panels.png) |

| Lab VMs (preview data) | Now playing (preview data) |
|---|---|
| ![Lab widget](screenshots/lab-widget.png) | ![Now playing widget](screenshots/now-playing.png) |

> The Wi-Fi name and local IP are blurred in the HUD screenshot.

## What's inside

### ruxchipher HUD: desktop widgets (`.config/conky/ruxchipher/`)
Four transparent widgets drawn from scratch in **Lua + cairo** on Conky. No Conky text templates are used.

- **`hud.lua`** (top right): clock; CPU / RAM / GPU gauge rings that turn red above 85%; temperatures; live network graph; disk, battery and fans; top processes.
  The GPU is only queried with `nvidia-smi` when its PCI runtime power state is already `active`, so the widget never wakes the dGPU and drains the battery.
- **`lab.lua`** (bottom right): status tiles for my KVM lab VMs (DC01, WIN11, KALI), with per-VM CPU % from `virsh domstats` and the isolated lab network state.
- **`left.lua`** (left side): a time-of-day greeting and rotating security tip; a **mission tracker** (countdown, objectives from `mission.txt`, commit streak and 28-day heatmap from my lab repo); Sydney **weather** (via `weather.py` and wttr.in) and a month calendar.
- **`media.lua`** (bottom left): now playing from any MPRIS player through `playerctl`, with album art (`art.sh`). It fades out when nothing is playing.
- **`common.lua`**: shared drawing helpers and palette.

GNOME has no wlr-layer-shell, so the widgets render through XWayland as `desktop`-type windows (`output_backend = 'x11'`).

### sentinel: host alerting (`.local/bin/ruxchipher-sentinel`)
A small Python service, run as a systemd user unit, that sends desktop notifications for:
- **failed authentication** read from the systemd journal: PAM failures (sudo, su, polkit, login screen), sudo wrong-password counts, SSH failed or invalid-user logins;
- **new listening TCP ports** (from `ss`), marked critical when they're not bound to localhost.

Alerts are de-duplicated and appended to `~/.local/state/ruxchipher-sentinel/events.log`.
It's a learning project for host-based detection, not a replacement for a real IDS/EDR.

### Terminal and GNOME
- **`.config/fastfetch/`**: terminal greeting with a shield logo, a time-based greeting, system info, and live lab VM and sentinel status.
- **`gnome/ddterm.dconf`**: drop-down terminal on **F12** (ddterm extension), Tokyo Night, fish, JetBrains Mono.
- **`gnome/clipboard-indicator.dconf`**: Windows-style clipboard history on **Super+V** (Clipboard Indicator extension).

## Requirements

Arch packages: `conky` (1.25+, built with Lua + cairo), `playerctl`, `imagemagick`, `python`, `libvirt`, `libnotify`, `fastfetch`, `ttf-jetbrains-mono-nerd`.
GNOME extensions: [ddterm](https://extensions.gnome.org/extension/3780/ddterm/) and [Clipboard Indicator](https://extensions.gnome.org/extension/779/clipboard-indicator/).

## Install

```bash
git clone https://github.com/Siddique-12300983/ruxchipher-dotfiles.git
cd ruxchipher-dotfiles
cp -r .config/* ~/.config/
cp .local/bin/ruxchipher-sentinel ~/.local/bin/ && chmod +x ~/.local/bin/ruxchipher-sentinel

systemctl --user daemon-reload
systemctl --user enable --now ruxchipher-sentinel.service

dconf load /org/gnome/shell/extensions/ddterm/ < gnome/ddterm.dconf
dconf load /org/gnome/shell/extensions/clipboard-indicator/ < gnome/clipboard-indicator.dconf
```

Then log out and back in. The widgets start from `~/.config/autostart/ruxchipher-hud.desktop`.

> **Note:** the `.conf` files and the autostart entry use absolute paths under `/home/ruxchipher`.
> If your username is different, replace that path, for example:
> `grep -rl /home/ruxchipher ~/.config/conky/ruxchipher ~/.config/autostart | xargs sed -i "s|/home/ruxchipher|$HOME|g"`

## Customise

- **Mission:** edit `~/.config/conky/ruxchipher/mission.txt` and change `[ ]` to `[x]` as you finish objectives. It reloads by itself.
- **Weather city:** change `CITY` in `weather.py`.
- **Lab VMs:** edit the `VMS` table at the top of `lab.lua`, so the names match `virsh list --all`.

## License

MIT
