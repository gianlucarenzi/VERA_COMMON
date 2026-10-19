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

# the monitor to use (x y w h): the primary one (several monitors at home),
# else the whole screen. EMU_MONITOR=<xrandr name> picks another one.
monitor() {
	xrandr --listmonitors 2>/dev/null | awk -v want="$EMU_MONITOR" '
		NR > 1 { split($3, g, /[\/x+]/)	# w/mmw x h/mmh + x + y
			if (want != "" ? $NF == want : $2 ~ /\*/) { print g[5], g[6], g[1], g[3]; exit } }'
}
geo=$(monitor)
[ -n "$geo" ] || geo="0 0 $(xdpyinfo | awk '/dimensions/ { split($2, d, "x"); print d[1], d[2] }')"
read mx my sw sh <<EOF
$geo
EOF

"$@" > "${EMU_LOG:-/dev/null}" 2>&1 &
pid=$!

# pid and its descendants: the command may be a make or a shell that starts
# the emulator
tree() {
	echo "$1"
	for c in $(pgrep -P "$1"); do tree "$c"; done
}

find_win() {			# $1 = name regexp, $2 = tries of 0.1 s
	i=0
	while [ $i -lt "${2:-100}" ]; do
		ps=" $(tree "$pid" | tr '\n' ' ')"
		id=$(wmctrl -lp | awk -v ps="$ps" -v n="$1" 'index(ps, " " $3 " ") && tolower($0) ~ tolower(n) { print $1; exit }')
		[ -n "$id" ] && { echo "$id"; return; }
		i=$((i + 1)); sleep 0.1
	done
}

main=$(find_win "$name")
vera=$(find_win 'VERA' 20)	# the X16 has none
if [ -n "$main" ]; then
	wmctrl -i -r "$main" -e 0,$mx,$((my + 24)),-1,-1
	wmctrl -i -r "$main" -b add,above
fi
if [ -n "$vera" ]; then
	# VERA 640x480 at the bottom-right, above the bottom panel (24 px)
	wmctrl -i -r "$vera" -e 0,$((mx + sw - 640)),$((my + sh - 24 - 480 - 30)),-1,-1
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
