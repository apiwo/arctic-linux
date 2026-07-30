#!/bin/sh
# tui.sh - the Arctic Linux text interface toolkit
#
# Pure POSIX sh drawing on a raw tty. No ncurses, no dialog, no GNU utilities:
# the installer has to work on the minimal ISO where /bin is busybox and toybox.
# shellcheck shell=sh disable=SC2039,SC2059

# --------------------------------------------------------------------- palette
E=$(printf '\033')
CSI="$E["

t_reset="${CSI}0m"      ; t_bold="${CSI}1m"     ; t_dim="${CSI}2m"
t_ital="${CSI}3m"       ; t_under="${CSI}4m"    ; t_rev="${CSI}7m"

# Arctic gradient, violet -> indigo -> ice -> teal.
c_vio="${CSI}38;5;99m"  ; c_ind="${CSI}38;5;69m"  ; c_ice="${CSI}38;5;81m"
c_teal="${CSI}38;5;44m" ; c_mint="${CSI}38;5;49m" ; c_snow="${CSI}38;5;231m"
c_grey="${CSI}38;5;245m"; c_dark="${CSI}38;5;238m"; c_red="${CSI}38;5;203m"
c_amb="${CSI}38;5;215m" ; c_bgsel="${CSI}48;5;24m"; c_bgbar="${CSI}48;5;54m"

# The five-stop ramp used to colour the logo and rules.
RAMP="99 63 69 75 81 44 49"

# ------------------------------------------------------------------- terminal
TUI_ROWS=24
TUI_COLS=80
_tui_stty=""

tui_size() {
	if command -v stty >/dev/null 2>&1; then
		set -- $(stty size 2>/dev/null)
		[ -n "${1:-}" ] && TUI_ROWS=$1
		[ -n "${2:-}" ] && TUI_COLS=$2
	fi
	[ "${TUI_ROWS:-0}" -lt 10 ] && TUI_ROWS=24
	[ "${TUI_COLS:-0}" -lt 40 ] && TUI_COLS=80
}

tui_init() {
	tui_size
	_tui_stty=$(stty -g 2>/dev/null || echo "")
	printf '%s?1049h%s?25l' "$CSI" "$CSI"   # alt screen, hide cursor
	tui_clear
	trap 'tui_done; exit 130' INT TERM
}

tui_done() {
	printf '%s?25h%s?1049l%s' "$CSI" "$CSI" "$t_reset"
	[ -n "$_tui_stty" ] && stty "$_tui_stty" 2>/dev/null || stty sane 2>/dev/null
}

tui_clear() { printf '%s2J%s1;1H' "$CSI" "$CSI"; }
tui_at()    { printf '%s%s;%sH' "$CSI" "$1" "$2"; }
tui_el()    { printf '%sK' "$CSI"; }

# Centre text of visible width $2 on a line.
_centre() { echo $(( (TUI_COLS - $1) / 2 + 1 )); }

# Repeat a character n times without seq or GNU printf tricks.
_rep() {
	_r_n=$2; _r_s=""
	while [ "$_r_n" -gt 0 ]; do _r_s="$_r_s$1"; _r_n=$((_r_n-1)); done
	printf '%s' "$_r_s"
}

# ------------------------------------------------------------------- key input
# Returns one of: up down left right enter space tab esc bksp home end
# pgup pgdn, or the literal character.
tui_key() {
	stty raw -echo 2>/dev/null
	k=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n\t')
	case "$k" in
	1b)
		# Possible escape sequence. A bare ESC has nothing queued behind it.
		k2=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n\t')
		if [ "$k2" = "5b" ] || [ "$k2" = "4f" ]; then
			k3=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n\t')
			case "$k3" in
			41) printf 'up'    ;;
			42) printf 'down'  ;;
			43) printf 'right' ;;
			44) printf 'left'  ;;
			48) printf 'home'  ;;
			46) printf 'end'   ;;
			35) dd bs=1 count=1 >/dev/null 2>&1; printf 'pgup' ;;
			36) dd bs=1 count=1 >/dev/null 2>&1; printf 'pgdn' ;;
			*)  printf 'esc'   ;;
			esac
		else
			printf 'esc'
		fi ;;
	0a|0d) printf 'enter' ;;
	20)    printf 'space' ;;
	09)    printf 'tab'   ;;
	7f|08) printf 'bksp'  ;;
	03)    printf 'ctrlc' ;;
	"")    printf 'none'  ;;
	*)
		# Turn the hex byte back into the character it stands for.
		printf '%b' "\\0$(printf '%o' "$((0x$k))")" ;;
	esac
	stty -raw echo 2>/dev/null
}

# ---------------------------------------------------------------------- chrome
# The Arctic 'A', coloured along the gradient ramp, drawn at a given origin.
TUI_LOGO='                   .xx
                   xxxx
                  xxxxxx
                 xxxxxxx
                xxxxxxxxx
               .xx ;xxxxxx
               xx   xxxxxxx
              xx+    xxxxxx+
             xxx      xxxxxx
            xxx        xxxxxx
           .xx         ;xxxxxx
           xx           xxxxxxx
          xx+            xxxxxx;
         xxxxxxxxxxxxxxxxxxxxxxx
        xxx                xxxxxx
       .xx                 +xxxxxx
       xx                   xxxxxxx
      xx+                    xxxxxx:
     xxx                      xxxxxx
    xxxx                      xxxxxxx
 xxxxxxxxx;:              :xxxxxxxxxxxxx:'

tui_logo() {
	row=${1:-2} col=${2:-}
	[ -n "$col" ] || col=$(_centre 42)
	i=0
	printf '%s' "$TUI_LOGO" | while IFS= read -r line; do
		# Walk the ramp top to bottom so the mark fades violet -> teal.
		n=$(( i * 7 / 21 + 1 )); [ "$n" -gt 7 ] && n=7
		col_code=$(printf '%s' "$RAMP" | cut -d' ' -f"$n")
		tui_at $((row + i)) "$col"
		printf '%s38;5;%sm%s%s' "$CSI" "$col_code" "$line" "$t_reset"
		i=$((i+1))
	done
}

# Title bar across the top plus a gradient rule.
tui_header() {
	title=$1 sub=${2:-}
	tui_at 1 1
	printf '%s%s%s' "$c_bgbar$c_snow$t_bold" "$(_rep ' ' "$TUI_COLS")" "$t_reset"
	tui_at 1 3
	printf '%s%s Arctic Linux %s%s' "$c_bgbar$c_snow$t_bold" "$t_reset$c_bgbar$c_snow" \
		"$title" "$t_reset"
	if [ -n "$sub" ]; then
		r=$(( ${#sub} + 3 ))
		tui_at 1 $((TUI_COLS - r))
		printf '%s%s %s' "$c_bgbar$c_ice" "$sub" "$t_reset"
	fi
	# Gradient rule under the bar.
	tui_at 2 1
	seg=$(( TUI_COLS / 7 + 1 ))
	for n in $RAMP; do
		printf '%s38;5;%sm%s' "$CSI" "$n" "$(_rep '=' "$seg")"
	done
	printf '%s' "$t_reset"
}

tui_footer() {
	tui_at "$TUI_ROWS" 1
	printf '%s%s%s' "$c_dark" "$(_rep ' ' "$TUI_COLS")" "$t_reset"
	tui_at "$TUI_ROWS" 3
	printf '%s%s%s' "$c_grey" "$*" "$t_reset"
}

# A framed panel. tui_box row col height width [title]
tui_box() {
	r=$1 c=$2 h=$3 w=$4 title=${5:-}
	inner=$((w - 2))
	tui_at "$r" "$c"; printf '%s+%s+%s' "$c_ind" "$(_rep '-' "$inner")" "$t_reset"
	i=1
	while [ "$i" -lt $((h - 1)) ]; do
		tui_at $((r + i)) "$c"
		printf '%s|%s%s|%s' "$c_ind" "$(_rep ' ' "$inner")" "$c_ind" "$t_reset"
		i=$((i+1))
	done
	tui_at $((r + h - 1)) "$c"; printf '%s+%s+%s' "$c_ind" "$(_rep '-' "$inner")" "$t_reset"
	if [ -n "$title" ]; then
		tui_at "$r" $((c + 3))
		printf '%s %s %s' "$c_teal$t_bold" "$title" "$t_reset"
	fi
}

# ----------------------------------------------------------------------- menu
# tui_menu "Title" "hint" "key|label|description" ...
# Result: TUI_CHOICE holds the selected key, TUI_INDEX its position.
TUI_CHOICE=""
TUI_INDEX=0

# Draw a single menu row. Kept separate so navigation can repaint just the two
# rows that changed instead of the whole screen.
_menu_row() {
	_mr_row=$1 _mr_left=$2 _mr_w=$3 _mr_sel=$4 _mr_item=$5
	lab=$(printf '%s' "$_mr_item" | cut -d'|' -f2)
	dsc=$(printf '%s' "$_mr_item" | cut -d'|' -f3)
	tui_at "$_mr_row" "$_mr_left"
	if [ "$_mr_sel" = "1" ]; then
		printf '%s %s %-22s %s%-*.*s%s' \
			"$c_bgsel$c_snow$t_bold" ">" "$lab" \
			"$c_bgsel$c_ice" $((_mr_w - 27)) $((_mr_w - 27)) "$dsc" "$t_reset"
	else
		printf '   %s%-22s%s %s%-*.*s%s' \
			"$c_snow" "$lab" "$t_reset" "$c_grey" \
			$((_mr_w - 26)) $((_mr_w - 26)) "$dsc" "$t_reset"
	fi
}

# tui_menu "Title" "hint" "key|label|description" ...
#
# The screen is drawn once. Moving the selection repaints exactly two rows - the
# one being left and the one being entered - because clearing and redrawing the
# whole screen on every keypress flickers badly on a VGA console and is
# genuinely unpleasant to look at.
tui_menu() {
	m_title=$1; m_hint=$2; shift 2
	m_n=$#
	[ "$m_n" -gt 0 ] || return 1
	sel=${TUI_MENU_START:-1}
	TUI_MENU_START=1
	redraw=1
	last_rows=0; last_cols=0

	while :; do
		tui_size
		# Only a resize justifies repainting everything.
		if [ "$TUI_ROWS" != "$last_rows" ] || [ "$TUI_COLS" != "$last_cols" ]; then
			redraw=1
			last_rows=$TUI_ROWS; last_cols=$TUI_COLS
		fi

		top=4
		listw=$(( TUI_COLS - 8 ))
		[ "$listw" -gt 72 ] && listw=72
		left=$(_centre "$listw")

		if [ "$redraw" = "1" ]; then
			tui_clear
			tui_header "$m_title" "$m_hint"
			tui_at "$top" "$left"
			printf '%s%s%s' "$c_snow$t_bold" "$m_title" "$t_reset"
			tui_at $((top + 1)) "$left"
			printf '%s%s%s' "$c_grey" "$(_rep '-' "$listw")" "$t_reset"
			i=1
			for item in "$@"; do
				s_flag=0; [ "$i" = "$sel" ] && s_flag=1
				_menu_row $((top + 2 + i)) "$left" "$listw" "$s_flag" "$item"
				i=$((i+1))
			done
			tui_footer "up/down move   enter select   $m_hint"
			redraw=0
		fi

		prev=$sel
		k=$(tui_key)
		case "$k" in
		up|k)     sel=$((sel - 1)); [ "$sel" -lt 1 ] && sel=$m_n ;;
		down|j)   sel=$((sel + 1)); [ "$sel" -gt "$m_n" ] && sel=1 ;;
		home)     sel=1 ;;
		end)      sel=$m_n ;;
		enter)
			i=1
			for item in "$@"; do
				if [ "$i" = "$sel" ]; then
					TUI_CHOICE=$(printf '%s' "$item" | cut -d'|' -f1)
					TUI_INDEX=$sel
					return 0
				fi
				i=$((i+1))
			done ;;
		esc|q)    TUI_CHOICE=""; return 1 ;;
		ctrlc)    tui_done; exit 130 ;;
		[1-9])
			if [ "$k" -le "$m_n" ]; then sel=$k; fi ;;
		esac

		# Repaint only what actually changed.
		if [ "$sel" != "$prev" ]; then
			i=1
			for item in "$@"; do
				if [ "$i" = "$prev" ]; then
					_menu_row $((top + 2 + i)) "$left" "$listw" 0 "$item"
				elif [ "$i" = "$sel" ]; then
					_menu_row $((top + 2 + i)) "$left" "$listw" 1 "$item"
				fi
				i=$((i+1))
			done
		fi
	done
}

# ------------------------------------------------------------------- checklist
# tui_checklist "Title" "hint" "key|label|desc|on" ...
# Result: TUI_SELECTED is a space separated list of chosen keys.
TUI_SELECTED=""

_check_row() {
	_cr_row=$1 _cr_left=$2 _cr_w=$3 _cr_cur=$4 _cr_on=$5 _cr_item=$6
	lab=$(printf '%s' "$_cr_item" | cut -d'|' -f2)
	dsc=$(printf '%s' "$_cr_item" | cut -d'|' -f3)
	mark=" "; [ "$_cr_on" = "1" ] && mark="x"
	tui_at "$_cr_row" "$_cr_left"
	if [ "$_cr_cur" = "1" ]; then
		printf '%s [%s] %-20s %s%-*.*s%s' "$c_bgsel$c_snow$t_bold" "$mark" "$lab" \
			"$c_bgsel$c_ice" $((_cr_w-28)) $((_cr_w-28)) "$dsc" "$t_reset"
	else
		m_col=$c_grey
		[ "$mark" = "x" ] && m_col=$c_mint
		printf ' %s[%s]%s %s%-20s%s %s%-*.*s%s' "$m_col" "$mark" "$t_reset" \
			"$c_snow" "$lab" "$t_reset" "$c_grey" \
			$((_cr_w-27)) $((_cr_w-27)) "$dsc" "$t_reset"
	fi
}

# tui_checklist "Title" "hint" "key|label|desc|on" ...
# Same repaint discipline as tui_menu: draw once, then touch only what moved.
tui_checklist() {
	m_title=$1; m_hint=$2; shift 2
	m_n=$#
	sel=1
	state=""
	i=1
	for item in "$@"; do
		on=$(printf '%s' "$item" | cut -d'|' -f4)
		[ "$on" = "on" ] && state="$state $i"
		i=$((i+1))
	done
	redraw=1; last_rows=0; last_cols=0

	is_on() { case " $state " in *" $1 "*) return 0 ;; esac; return 1; }

	while :; do
		tui_size
		if [ "$TUI_ROWS" != "$last_rows" ] || [ "$TUI_COLS" != "$last_cols" ]; then
			redraw=1; last_rows=$TUI_ROWS; last_cols=$TUI_COLS
		fi
		top=4
		listw=$(( TUI_COLS - 8 )); [ "$listw" -gt 72 ] && listw=72
		left=$(_centre "$listw")

		if [ "$redraw" = "1" ]; then
			tui_clear
			tui_header "$m_title" "$m_hint"
			tui_at "$top" "$left"; printf '%s%s%s' "$c_snow$t_bold" "$m_title" "$t_reset"
			tui_at $((top+1)) "$left"; printf '%s%s%s' "$c_grey" "$(_rep '-' "$listw")" "$t_reset"
			i=1
			for item in "$@"; do
				c_flag=0; [ "$i" = "$sel" ] && c_flag=1
				o_flag=0; is_on "$i" && o_flag=1
				_check_row $((top + 2 + i)) "$left" "$listw" "$c_flag" "$o_flag" "$item"
				i=$((i+1))
			done
			tui_footer "space toggle   enter confirm   $m_hint"
			redraw=0
		fi

		prev=$sel; toggled=0
		k=$(tui_key)
		case "$k" in
		up|k)   sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=$m_n ;;
		down|j) sel=$((sel+1)); [ "$sel" -gt "$m_n" ] && sel=1 ;;
		space)
			if is_on "$sel"; then
				state=$(printf '%s' "$state" | tr ' ' '\n' | grep -vx "$sel" | tr '\n' ' ')
			else
				state="$state $sel"
			fi
			toggled=1 ;;
		enter)
			TUI_SELECTED=""
			i=1
			for item in "$@"; do
				is_on "$i" && \
					TUI_SELECTED="$TUI_SELECTED $(printf '%s' "$item" | cut -d'|' -f1)"
				i=$((i+1))
			done
			TUI_SELECTED=$(printf '%s' "$TUI_SELECTED" | sed 's/^ *//')
			return 0 ;;
		esc|q) return 1 ;;
		ctrlc) tui_done; exit 130 ;;
		esac

		if [ "$sel" != "$prev" ] || [ "$toggled" = "1" ]; then
			i=1
			for item in "$@"; do
				if [ "$i" = "$prev" ] || [ "$i" = "$sel" ]; then
					c_flag=0; [ "$i" = "$sel" ] && c_flag=1
					o_flag=0; is_on "$i" && o_flag=1
					_check_row $((top + 2 + i)) "$left" "$listw" "$c_flag" "$o_flag" "$item"
				fi
				i=$((i+1))
			done
		fi
	done
}

# ----------------------------------------------------------------------- input
# tui_input "Title" "prompt" [default] [hidden]
TUI_VALUE=""

# tui_input "Title" "prompt" [default] [hidden]
#
# The frame is drawn once; each keystroke repaints only the value line. Redrawing
# the whole box per character made typing flicker.
tui_input() {
	i_title=$1; i_prompt=$2; i_def=${3:-}; i_hide=${4:-}
	val=$i_def
	redraw=1; last_cols=0
	while :; do
		tui_size
		[ "$TUI_COLS" != "$last_cols" ] && { redraw=1; last_cols=$TUI_COLS; }
		w=$(( TUI_COLS - 12 )); [ "$w" -gt 64 ] && w=64
		left=$(_centre "$w")
		top=$(( TUI_ROWS / 2 - 4 ))

		if [ "$redraw" = "1" ]; then
			tui_clear
			tui_header "$i_title"
			tui_box "$top" "$left" 7 "$w" "$i_title"
			tui_at $((top+2)) $((left+3))
			printf '%s%s%s' "$c_ice" "$i_prompt" "$t_reset"
			[ -n "$i_def" ] && {
				tui_at $((top+5)) $((left+3))
				printf '%sdefault: %s%s' "$c_grey" "$i_def" "$t_reset"
			}
			tui_footer "type to edit   enter accept   esc back"
			redraw=0
		fi

		# Just the value line.
		tui_at $((top+4)) $((left+3))
		show=$val
		[ -n "$i_hide" ] && show=$(_rep '*' "${#val}")
		pad=$(( w - 8 - ${#show} )); [ "$pad" -lt 0 ] && pad=0
		printf '%s %s%s%s' "$c_bgsel$c_snow" "$show" "$(_rep ' ' "$pad")" "$t_reset"

		k=$(tui_key)
		case "$k" in
		enter) TUI_VALUE=$val; return 0 ;;
		bksp)  val=$(printf '%s' "$val" | sed 's/.$//') ;;
		esc)   TUI_VALUE=""; return 1 ;;
		ctrlc) tui_done; exit 130 ;;
		up|down|left|right|tab|home|end|pgup|pgdn|none) ;;
		space) val="$val " ;;
		*)     val="$val$k" ;;
		esac
	done
}

tui_password() {
	while :; do
		tui_input "$1" "$2" "" hidden || return 1
		p1=$TUI_VALUE
		[ -n "$p1" ] || { tui_msgbox "Password" "The password cannot be empty." ; continue; }
		tui_input "$1" "Repeat the password" "" hidden || return 1
		if [ "$p1" = "$TUI_VALUE" ]; then TUI_VALUE=$p1; return 0; fi
		tui_msgbox "Password" "Those did not match. Try again."
	done
}

# --------------------------------------------------------------------- dialogs
tui_msgbox() {
	m_title=$1; shift
	tui_size; tui_clear
	tui_header "$m_title"
	w=$(( TUI_COLS - 16 )); [ "$w" -gt 60 ] && w=60
	left=$(_centre "$w")
	top=$(( TUI_ROWS / 2 - 4 ))
	# Wrap the message by hand: fold(1) is not guaranteed present.
	lines=""; cur=""
	for word in $*; do
		if [ $(( ${#cur} + ${#word} + 1 )) -gt $((w - 6)) ]; then
			lines="$lines$cur
"; cur=$word
		else
			[ -n "$cur" ] && cur="$cur $word" || cur=$word
		fi
	done
	lines="$lines$cur"
	n=$(printf '%s\n' "$lines" | wc -l)
	tui_box "$top" "$left" $((n + 6)) "$w" "$m_title"
	i=0
	printf '%s\n' "$lines" | while IFS= read -r l; do
		tui_at $((top + 2 + i)) $((left + 3)); printf '%s%s%s' "$c_snow" "$l" "$t_reset"
		i=$((i+1))
	done
	tui_at $((top + n + 4)) $((left + 3))
	printf '%s press enter %s' "$c_bgsel$c_snow$t_bold" "$t_reset"
	tui_footer "enter continue"
	while :; do
		k=$(tui_key)
		case "$k" in enter|esc|space) return 0 ;; ctrlc) tui_done; exit 130 ;; esac
	done
}

# Returns 0 for yes, 1 for no. Third argument "no" makes No the default.
tui_yesno() {
	y_title=$1; y_msg=$2; def=${3:-yes}
	cur=$def
	while :; do
		tui_size; tui_clear
		tui_header "$y_title"
		w=$(( TUI_COLS - 16 )); [ "$w" -gt 62 ] && w=62
		left=$(_centre "$w"); top=$(( TUI_ROWS / 2 - 4 ))
		tui_box "$top" "$left" 8 "$w" "$y_title"
		tui_at $((top+2)) $((left+3)); printf '%s%.*s%s' "$c_snow" $((w-6)) "$y_msg" "$t_reset"
		tui_at $((top+5)) $((left+3))
		if [ "$cur" = "yes" ]; then
			printf '%s  Yes  %s   %s  No  %s' "$c_bgsel$c_snow$t_bold" "$t_reset" "$c_grey" "$t_reset"
		else
			printf '%s  Yes  %s   %s  No  %s' "$c_grey" "$t_reset" "$c_bgsel$c_snow$t_bold" "$t_reset"
		fi
		tui_footer "left/right choose   enter confirm"
		k=$(tui_key)
		case "$k" in
		left|right|tab) [ "$cur" = "yes" ] && cur=no || cur=yes ;;
		y|Y) return 0 ;;
		n|N) return 1 ;;
		enter) [ "$cur" = "yes" ] && return 0 || return 1 ;;
		esc) return 1 ;;
		ctrlc) tui_done; exit 130 ;;
		esac
	done
}

# ---------------------------------------------------------------------- gauge
# A full-width progress display used during the install run.
TUI_TASK_TOTAL=1
TUI_TASK_DONE=0

tui_gauge_init() { TUI_TASK_TOTAL=${1:-1}; TUI_TASK_DONE=0; tui_clear; }

tui_gauge() {
	label=$1; pct=${2:-}
	[ -n "$pct" ] || {
		TUI_TASK_DONE=$((TUI_TASK_DONE + 1))
		pct=$(( TUI_TASK_DONE * 100 / TUI_TASK_TOTAL ))
	}
	[ "$pct" -gt 100 ] && pct=100
	tui_size
	tui_header "Installing" "$pct%"
	tui_logo 4
	row=$(( TUI_ROWS - 6 ))
	w=$(( TUI_COLS - 12 )); [ "$w" -gt 64 ] && w=64
	left=$(_centre "$w")
	tui_at "$row" "$left"; tui_el
	printf '%s%-*.*s%s' "$c_snow" "$w" "$w" "$label" "$t_reset"
	fill=$(( pct * (w - 8) / 100 ))
	tui_at $((row+1)) "$left"
	printf '%s' "$c_teal"
	i=0
	while [ "$i" -lt $((w - 8)) ]; do
		if [ "$i" -lt "$fill" ]; then
			n=$(( i * 7 / (w - 8) + 1 )); [ "$n" -gt 7 ] && n=7
			printf '%s38;5;%sm#' "$CSI" "$(printf '%s' "$RAMP" | cut -d' ' -f"$n")"
		else
			printf '%s.' "$c_dark"
		fi
		i=$((i+1))
	done
	printf '%s %3d%%%s' "$c_snow$t_bold" "$pct" "$t_reset"
	tui_at $((row+3)) "$left"; tui_el
	printf '%s%s%s' "$c_grey" "${TUI_GAUGE_NOTE:-}" "$t_reset"
}

# Show a scrolling log line beneath the gauge without disturbing it.
tui_log_line() {
	row=$(( TUI_ROWS - 2 ))
	tui_at "$row" 3; tui_el
	printf '%s%.*s%s' "$c_dark" $((TUI_COLS - 6)) "$*" "$t_reset"
}

# Splash used at the very start of the installer.
tui_splash() {
	tui_size; tui_clear
	tui_logo 2
	row=25
	msg="Arctic Linux"
	tui_at "$row" "$(_centre 12)"
	printf '%s%s%s' "$c_snow$t_bold" "$msg" "$t_reset"
	sub=${1:-"system installer"}
	tui_at $((row+1)) "$(_centre ${#sub})"
	printf '%s%s%s' "$c_grey" "$sub" "$t_reset"
}
