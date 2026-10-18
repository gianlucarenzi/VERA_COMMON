#!/bin/sh
# run_emu.sh - launch an emulator with the window layout of the small laptop
# screen: main window small at the top-left, VERA window at the bottom-right,
# never overlapping, both above the terminal, keyboard focus on the main one.
#
# Usage: tools/run_emu.sh <main window name regexp> <command...>
#   e.g. tools/run_emu.sh 'VICE' x64sc -vera ... prog.prg
#        tools/run_emu.sh 'Atari' atari800 -verax16 ... prog.xex
# Env: EMU_SHOT=<file.png> -> after EMU_WAIT seconds (default 10) save a
#      screenshot of both windows (<file>-main.png, <file>-vera.png) and quit.

name="$1"; shift
"$@" > "${EMU_LOG:-/dev/null}" 2>&1 &
pid=$!

find_win() {
	i=0
	while [ $i -lt 100 ]; do
		id=$(wmctrl -lp | awk -v p="$pid" -v n="$1" '$3 == p && tolower($0) ~ tolower(n) { print $1; exit }')
		[ -n "$id" ] && { echo "$id"; return; }
		i=$((i + 1)); sleep 0.1
	done
}

sw=$(xdpyinfo | awk '/dimensions/ { split($2, d, "x"); print d[1] }')
sh=$(xdpyinfo | awk '/dimensions/ { split($2, d, "x"); print d[2] }')

main=$(find_win "$name")
vera=$(find_win 'VERA')
if [ -n "$main" ]; then
	wmctrl -i -r "$main" -e 0,0,24,-1,-1
	wmctrl -i -r "$main" -b add,above
fi
if [ -n "$vera" ]; then
	# VERA 640x480 at the bottom-right, above the bottom panel (24 px)
	wmctrl -i -r "$vera" -e 0,$((sw - 640)),$((sh - 24 - 480 - 30)),-1,-1
	wmctrl -i -r "$vera" -b add,above
fi
[ -n "$main" ] && xdotool windowactivate --sync "$(printf %d "$main")" 2>/dev/null

if [ -n "$EMU_SHOT" ]; then
	sleep "${EMU_WAIT:-10}"
	b="${EMU_SHOT%.png}"
	[ -n "$main" ] && import -window "$main" "$b-main.png"
	[ -n "$vera" ] && import -window "$vera" "$b-vera.png"
	kill "$pid"
fi
wait "$pid"
