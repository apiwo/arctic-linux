# ~/.zprofile - login shell, runs once per session.

# Start a Wayland session automatically on tty1 when no display manager runs.
if [[ -z $WAYLAND_DISPLAY && -z $DISPLAY && $XDG_VTNR == 1 ]]; then
	[[ -x /usr/bin/Hyprland ]] && exec Hyprland
	[[ -x /usr/bin/niri ]] && exec niri --session
fi
