#!/usr/bin/env bash
# ruxchipher dotfiles installer: Arch Linux + GNOME (Wayland).
#
#   ./install.sh --user     widgets, scripts, terminal, GTK colours, icons, shortcuts (no root, except packages)
#   ./install.sh --system   boot splash, login screen, browser start page + theme, lid hook, Spotify theme (sudo)
#   ./install.sh --all      both
#
# Safe to re-run. Anything it replaces at system level is backed up with a .pre-ruxchipher suffix.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
OLD_HOME=/home/ruxchipher
PACKAGES=(conky playerctl imagemagick python libvirt libnotify fastfetch kitty git curl
          ttf-jetbrains-mono-nerd papirus-icon-theme plymouth gcc libx11 libxext python-gobject xorg-xrandr)
EXTENSIONS=(ddterm@amezin.github.com clipboard-indicator@tudmotu.com
            user-theme@gnome-shell-extensions.gcampax.github.com tilingshell@ferrarodomenico.com)
SPICETIFY_VERSION=2.46.2

c() { printf '\033[38;2;125;207;255m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[38;2;255;158;100m  !\033[0m %s\n' "$*"; }

# Copy a file, rewriting the original home path to this user's home.
put() {
    local src=$1 dst=$2
    mkdir -p "$(dirname "$dst")"
    if grep -Iq . "$src" 2>/dev/null; then
        sed "s|$OLD_HOME|$HOME|g" "$src" > "$dst"
        if [ -x "$src" ]; then chmod +x "$dst"; fi
    else
        cp "$src" "$dst"
    fi
}

install_packages() {
    c "Installing packages"
    sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"
}

install_extensions() {
    c "Installing GNOME extensions"
    local ver; ver=$(gnome-shell --version | grep -o '[0-9]\+' | head -1)
    for uuid in "${EXTENSIONS[@]}"; do
        if gnome-extensions info "$uuid" >/dev/null 2>&1; then continue; fi
        local url
        url=$(curl -s "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$ver" |
              python3 -I -c 'import sys, json; print(json.load(sys.stdin)["download_url"])' 2>/dev/null) || true
        if [ -z "$url" ]; then warn "$uuid has no build for GNOME $ver, install it from extensions.gnome.org"; continue; fi
        local tmp; tmp=$(mktemp -d)
        curl -sL -o "$tmp/ext.zip" "https://extensions.gnome.org$url"
        gnome-extensions install --force "$tmp/ext.zip"
        rm -rf "$tmp"
    done
    local enabled; enabled=$(gsettings get org.gnome.shell enabled-extensions)
    for uuid in "${EXTENSIONS[@]}"; do
        case "$enabled" in *"$uuid"*) ;; *) enabled=$(python3 -I -c "import ast,sys; l=ast.literal_eval(sys.argv[1].replace('@as ','')); l.append(sys.argv[2]); print(l)" "$enabled" "$uuid") ;; esac
    done
    gsettings set org.gnome.shell enabled-extensions "$enabled"
}

install_user() {
    install_packages

    c "Copying configs and scripts"
    (cd "$REPO" && find .config .local .themes -type f) | while read -r f; do put "$REPO/$f" "$HOME/$f"; done
    chmod +x "$HOME"/.local/bin/{ruxchipher-sentinel,lab-up,lab-down,focus-mode,sentinel-report,ruxchipher-greet,ruxchipher-greeter} \
             "$HOME/.config/conky/ruxchipher/art.sh"

    c "Building conky-clickable (lets the HUD and weather icon receive clicks)"
    cc -O2 -o "$HOME/.local/bin/conky-clickable" "$HOME/.config/conky/ruxchipher/tools/conky-clickable.c" -lX11 -lXext

    c "Wallpaper"
    mkdir -p "$HOME/Pictures/Wallpapers"
    cp "$REPO/wallpapers/ruxchipher-tokyonight.png" "$HOME/Pictures/Wallpapers/"
    gsettings set org.gnome.desktop.background picture-uri "file://$HOME/Pictures/Wallpapers/ruxchipher-tokyonight.png"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/Pictures/Wallpapers/ruxchipher-tokyonight.png"

    c "Papirus-Tokyo icons (violet folders)"
    local T="$HOME/.local/share/icons/Papirus-Tokyo"
    mkdir -p "$T"
    sed -e 's/^Name=Papirus-Dark/Name=Papirus-Tokyo/' -e 's/^Inherits=.*/Inherits=Papirus-Dark,breeze-dark,hicolor/' \
        /usr/share/icons/Papirus-Dark/index.theme > "$T/index.theme"
    for d in /usr/share/icons/Papirus/*/places; do
        local size; size=$(basename "$(dirname "$d")")
        mkdir -p "$T/$size/places"
        for f in "$d"/folder-violet*.svg "$d"/user-violet*.svg; do
            [ -e "$f" ] || continue
            local b; b=$(basename "$f")
            ln -sf "$f" "$T/$size/places/$(echo "$b" | sed 's/^folder-violet/folder/; s/^user-violet/user/')"
        done
    done

    c "GNOME look"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Tokyo'
    gsettings set org.gnome.desktop.interface accent-color 'blue'
    gsettings set org.gnome.Epiphany homepage-url "file://$HOME/.local/share/ruxchipher/startpage/index.html" 2>/dev/null || true

    install_extensions
    dconf load /org/gnome/shell/extensions/ddterm/ < "$REPO/gnome/ddterm.dconf"
    dconf load /org/gnome/shell/extensions/clipboard-indicator/ < "$REPO/gnome/clipboard-indicator.dconf"
    dconf load /org/gnome/shell/extensions/tilingshell/ < "$REPO/gnome/tilingshell.dconf"
    # Tokyo Night top bar / menus: ~/.themes/ruxchipher, selected through the User Themes extension
    dconf write /org/gnome/shell/extensions/user-theme/name "'ruxchipher'"
    # Super+V opens the clipboard, so GNOME's notification list keeps only Super+M
    gsettings set org.gnome.shell.keybindings toggle-message-tray "['<Super>m']"

    c "Keyboard shortcuts"
    local schema=org.gnome.settings-daemon.plugins.media-keys
    local base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/
    local list; list=$(gsettings get $schema custom-keybindings)
    while IFS='|' read -r id name binding command; do
        [ -n "$id" ] || continue
        local path="$base$id/"
        gsettings set "$schema.custom-keybinding:$path" name "$name"
        gsettings set "$schema.custom-keybinding:$path" binding "$binding"
        gsettings set "$schema.custom-keybinding:$path" command "${command//$OLD_HOME/$HOME}"
        case "$list" in *"$path"*) ;; *) list=$(python3 -I -c "import ast,sys; l=ast.literal_eval(sys.argv[1].replace('@as ','')); l.append(sys.argv[2]); print(l)" "$list" "$path") ;; esac
    done < "$REPO/gnome/keybindings.txt"
    gsettings set $schema custom-keybindings "$list"

    c "Sentinel service"
    systemctl --user daemon-reload
    systemctl --user enable --now ruxchipher-sentinel.service ruxchipher-greeter.service

    python3 -I "$HOME/.config/conky/ruxchipher/weather.py" || true
    c "User setup done. Log out and back in to load the widgets and extensions."
}

backup() { [ -e "$1" ] && sudo cp -n "$1" "$1.pre-ruxchipher" || true; }

# Spicetify "text" theme with the TokyoNight scheme, for the Flatpak Spotify.
install_spotify_theme() {
    local sp=/var/lib/flatpak/app/com.spotify.Client/x86_64/stable/active/files/extra/share/spotify
    if [ ! -d "$sp" ]; then warn "Spotify (Flatpak) not installed, skipping the Spotify theme"; return; fi
    c "Spotify theme (Spicetify, text / TokyoNight)"
    mkdir -p "$HOME/.spicetify"
    curl -sL "https://github.com/spicetify/cli/releases/download/v$SPICETIFY_VERSION/spicetify-$SPICETIFY_VERSION-linux-amd64.tar.gz" |
        tar xz -C "$HOME/.spicetify"
    ln -sf "$HOME/.spicetify/spicetify" "$HOME/.local/bin/spicetify"
    # Spicetify patches Spotify's files: own them as this user instead of making them world-writable
    sudo chown -R "$(id -u):$(id -g)" "$sp" && sudo chmod -R go-w "$sp"
    spicetify config >/dev/null 2>&1 || true
    local t="$HOME/.config/spicetify/Themes/text"; mkdir -p "$t"
    for f in color.ini user.css; do
        curl -sL -o "$t/$f" "https://raw.githubusercontent.com/spicetify/spicetify-themes/master/text/$f"
    done
    spicetify config spotify_path "$sp" prefs_path "$HOME/.var/app/com.spotify.Client/config/spotify/prefs" \
        current_theme text color_scheme TokyoNight
    spicetify backup apply || warn "run Spotify once, close it, then: spicetify backup apply"
}

install_system() {
    c "Brand files + Plymouth theme"
    sudo install -d /usr/share/ruxchipher /usr/share/plymouth/themes/ruxchipher
    sudo install -m644 "$REPO"/system/brand/* /usr/share/ruxchipher/
    sudo install -m644 "$REPO"/system/plymouth/ruxchipher/* /usr/share/plymouth/themes/ruxchipher/

    c "Login screen (GDM)"
    sudo install -d /etc/dconf/profile /etc/dconf/db/gdm.d
    backup /etc/dconf/profile/gdm
    sudo install -m644 "$REPO/system/gdm/profile-gdm" /etc/dconf/profile/gdm
    sudo install -m644 "$REPO/system/gdm/01-ruxchipher" /etc/dconf/db/gdm.d/01-ruxchipher
    sudo dconf update

    c "Browser start page"
    local start="file://$HOME/.local/share/ruxchipher/startpage/index.html"
    sudo install -d /etc/opt/chrome/policies/managed
    sed "s|file://$OLD_HOME|file://$HOME|g" "$REPO/system/browser/chrome-policy.json" |
        sudo tee /etc/opt/chrome/policies/managed/ruxchipher-startpage.json >/dev/null
    if [ -d /usr/lib/firefox/distribution ]; then
        backup /usr/lib/firefox/distribution/policies.json
        sed "s|file://$OLD_HOME|file://$HOME|g" "$REPO/system/browser/firefox-policies.json" |
            sudo tee /usr/lib/firefox/distribution/policies.json >/dev/null
    fi

    c "Lid-hibernate hook"
    if grep -q 'resume=' /proc/cmdline; then
        sudo install -Dm755 "$REPO/system/sleep/lid-hibernate" /etc/systemd/system-sleep/lid-hibernate
        [ -e /sys/class/power_supply/ACAD ] || warn "no ACAD power supply here: edit on_battery() in /etc/systemd/system-sleep/lid-hibernate"
    else
        warn "hibernation is not configured (no resume= on the kernel command line), skipping the lid hook"
    fi

    c "Boot splash"
    local preset=/etc/mkinitcpio.d/linux.preset
    if [ -f /etc/kernel/cmdline ] && grep -q '^default_uki=' "$preset" 2>/dev/null; then
        local uki; uki=$(sed -n 's/^default_uki="\(.*\)"/\1/p' "$preset")
        [ -f "${uki%.efi}-backup.efi" ] || sudo cp "$uki" "${uki%.efi}-backup.efi"
        backup /etc/mkinitcpio.conf; backup /etc/kernel/cmdline; backup "$preset"
        grep -q '^HOOKS=.*plymouth' /etc/mkinitcpio.conf ||
            sudo sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' /etc/mkinitcpio.conf
        grep -qw splash /etc/kernel/cmdline ||
            sudo sed -i '1 s/$/ quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0/' /etc/kernel/cmdline
        sudo sed -i 's#^default_options=.*#default_options="--splash /usr/share/ruxchipher/splash.bmp"#' "$preset"
        sudo plymouth-set-default-theme ruxchipher
        sudo mkinitcpio -P
    else
        warn "this machine doesn't boot a mkinitcpio UKI; set up the splash by hand (see GUIDE.md, 'Boot splash on GRUB')"
        sudo plymouth-set-default-theme ruxchipher
    fi
    install_spotify_theme
    c "System setup done. Reboot to see the boot splash."
}

case "${1:-}" in
    --user)   install_user ;;
    --system) install_system ;;
    --all)    install_user; install_system ;;
    *)        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
