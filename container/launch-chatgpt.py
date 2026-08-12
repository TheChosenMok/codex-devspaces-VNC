#!/usr/bin/env python3
"""Launch the command from the RPM's desktop file with container-safe flags."""

import configparser
import os
import shlex
import sys


DESKTOP_FILE = "/opt/chatgpt-vnc/chatgpt.desktop"

parser = configparser.ConfigParser(interpolation=None, strict=False)
parser.optionxform = str
with open(DESKTOP_FILE, encoding="utf-8") as desktop_file:
    parser.read_file(desktop_file)

try:
    command = parser["Desktop Entry"]["Exec"]
except KeyError as exc:
    raise SystemExit(f"No Exec entry found in {DESKTOP_FILE}") from exc

argv = []
for item in shlex.split(command):
    # Desktop Entry field codes such as %U and %F are not arguments here.
    if len(item) == 2 and item.startswith("%"):
        continue
    argv.append(item.replace("%%", "%"))

argv.extend(shlex.split(os.environ.get("CHATGPT_EXTRA_ARGS", "")))
if not argv:
    raise SystemExit(f"Empty Exec entry in {DESKTOP_FILE}")

os.execvp(argv[0], argv)

