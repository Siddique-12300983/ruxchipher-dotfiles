#!/usr/bin/env python3
"""Fetch Sydney weather from wttr.in and write a simple key=value cache for left.lua."""
import json
import sys
import urllib.request
from pathlib import Path

CITY = "Sydney"
OUT = Path.home() / ".cache/ruxchipher/weather.txt"

try:
    with urllib.request.urlopen(f"https://wttr.in/{CITY}?format=j1", timeout=10) as r:
        d = json.load(r)
except Exception:
    sys.exit(0)  # keep the previous cache

cur = d["current_condition"][0]
lines = [
    f"city={CITY}",
    f"temp={cur['temp_C']}",
    f"feels={cur['FeelsLikeC']}",
    f"desc={cur['weatherDesc'][0]['value'].strip()}",
    f"code={cur['weatherCode']}",
    f"humidity={cur['humidity']}",
    f"wind={cur['windspeedKmph']}",
]
for i, day in enumerate(d["weather"][:3]):
    noon = day["hourly"][len(day["hourly"]) // 2]
    lines.append(f"day{i}={day['date']}|{day['maxtempC']}|{day['mintempC']}|{noon['weatherCode']}")

OUT.parent.mkdir(parents=True, exist_ok=True)
tmp = OUT.with_suffix(".tmp")
tmp.write_text("\n".join(lines) + "\n")
tmp.replace(OUT)
