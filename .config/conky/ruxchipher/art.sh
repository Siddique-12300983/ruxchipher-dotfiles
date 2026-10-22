#!/bin/sh
# Turn an MPRIS art URL (file:// or http[s]://) into a square PNG for media.lua.
url=$1; out=$2; tmp="$out.tmp"
case $url in
    file://*) src=$(printf '%s' "${url#file://}" | python3 -I -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))') ;;
    http://*|https://*) src="$out.dl"; curl -sL -m 10 "$url" -o "$src" || exit 0 ;;
    *) exit 0 ;;
esac
magick "$src" -resize 192x192^ -gravity center -extent 192x192 "png:$tmp" && mv "$tmp" "$out"
