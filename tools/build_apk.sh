#!/usr/bin/env bash
# Builds an installable APK from the project's current state, then installs it on
# the attached phone or emulator and launches the game.
#
#   ./tools/build_apk.sh                 build -> build/sky_duel.apk, install, launch
#   ./tools/build_apk.sh --build-only    only build (no adb needed)
#   ./tools/build_apk.sh /tmp/duel.apk   build to another path, then install it
#   ADB_SERIAL=emulator-5554 ./tools/build_apk.sh   pick a device when several are on
#
# Uses the "Android" debug export preset, signed with Godot's local debug
# keystore, so the result installs without extra signing setup. The previous APK
# is only replaced once the new one has been written.
#
# Environment overrides: GODOT (Godot binary), ADB (adb binary), ADB_SERIAL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

BUILD_ONLY=0
OUT=""
for arg in "$@"; do
	case "$arg" in
		--build-only|-b) BUILD_ONLY=1 ;;
		-*) echo "Unknown option: $arg" >&2; exit 2 ;;
		*)
			if [ -n "$OUT" ]; then
				echo "Only one output path may be given." >&2
				exit 2
			fi
			OUT="$arg"
			;;
	esac
done
OUT="${OUT:-$ROOT/build/sky_duel.apk}"
TMP="${OUT%.apk}.tmp.apk"

if [ ! -x "$GODOT" ]; then
	echo "Godot binary not found: $GODOT" >&2
	echo "Point GODOT at it, e.g. GODOT=/path/to/Godot ./tools/build_apk.sh" >&2
	exit 1
fi

# --- Build -------------------------------------------------------------------

mkdir -p "$(dirname "$OUT")"
trap 'rm -f "$TMP"' EXIT
rm -f "$TMP"

echo "Exporting $(basename "$OUT") from $ROOT ..."
"$GODOT" --headless --path "$ROOT" --export-debug "Android" "$TMP"

if [ ! -s "$TMP" ]; then
	echo "Export finished but wrote no APK: $TMP" >&2
	exit 1
fi

mv -f "$TMP" "$OUT"
echo "APK ready: $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"

if [ "$BUILD_ONLY" -eq 1 ]; then
	exit 0
fi

# --- Find adb ----------------------------------------------------------------

if [ -z "${ADB:-}" ]; then
	if command -v adb >/dev/null 2>&1; then
		ADB="$(command -v adb)"
	elif [ -x "${ANDROID_HOME:-}/platform-tools/adb" ]; then
		ADB="${ANDROID_HOME}/platform-tools/adb"
	elif [ -x "${ANDROID_SDK_ROOT:-}/platform-tools/adb" ]; then
		ADB="${ANDROID_SDK_ROOT}/platform-tools/adb"
	elif [ -x /opt/homebrew/share/android-commandlinetools/platform-tools/adb ]; then
		ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
	fi
fi
if [ -z "${ADB:-}" ] || [ ! -x "$ADB" ]; then
	echo "adb not found, so the APK could not be installed." >&2
	echo "Set ADB=/path/to/adb, or use --build-only to skip installing." >&2
	echo "The APK is ready at: $OUT" >&2
	exit 1
fi

# --- Find a device -----------------------------------------------------------

SERIALS=""
UNAUTHORIZED=0
OFFLINE=0

# Reads `adb devices` into SERIALS (usable devices), UNAUTHORIZED and OFFLINE.
scan_devices() {
	SERIALS=""
	UNAUTHORIZED=0
	OFFLINE=0
	local line serial state
	while IFS= read -r line; do
		serial="$(printf '%s' "$line" | awk 'NF {print $1}')"
		state="$(printf '%s' "$line" | awk 'NF {print $2}')"
		case "$state" in
			device) SERIALS="$SERIALS $serial" ;;
			unauthorized) UNAUTHORIZED=$((UNAUTHORIZED + 1)) ;;
			offline) OFFLINE=$((OFFLINE + 1)) ;;
		esac
	done <<< "$("$ADB" devices 2>/dev/null || true)"
	SERIALS="$(printf '%s' "$SERIALS" | sed 's/^ *//')"
}

scan_devices

# A booting emulator, or a phone that just woke up, is listed as offline until it
# finishes connecting: give it a moment instead of failing straight away.
if [ -z "$SERIALS" ] && [ "$OFFLINE" -gt 0 ]; then
	echo "A device is attached but not ready yet, waiting for it ..."
	"$ADB" reconnect offline >/dev/null 2>&1 || true
	for _ in $(seq 1 10); do
		sleep 1
		scan_devices
		[ -n "$SERIALS" ] && break
	done
fi

if [ -z "$SERIALS" ]; then
	if [ "$UNAUTHORIZED" -gt 0 ]; then
		echo "A device is attached but not authorized, so nothing was installed." >&2
		echo "Accept the USB debugging prompt on the phone (or revoke and" >&2
		echo "re-authorize it) and run this again." >&2
	elif [ "$OFFLINE" -gt 0 ]; then
		echo "A device is attached but offline, so nothing was installed." >&2
		echo "An emulator that is still booting shows up this way: wait for it to" >&2
		echo "finish, or restart it, then run this again." >&2
	else
		echo "No phone or emulator is attached, so nothing was installed." >&2
		echo "Start an emulator or plug in a phone with USB debugging enabled." >&2
	fi
	echo "The APK is ready at: $OUT" >&2
	exit 1
fi

COUNT="$(printf '%s\n' $SERIALS | wc -l | tr -d ' ')"
if [ -n "${ADB_SERIAL:-}" ]; then
	SERIAL="$ADB_SERIAL"
elif [ "$COUNT" -eq 1 ]; then
	SERIAL="$SERIALS"
else
	echo "More than one device is attached:" >&2
	for serial in $SERIALS; do
		echo "  $serial" >&2
	done
	echo "Pick one with ADB_SERIAL=<serial> ./tools/build_apk.sh" >&2
	echo "The APK is ready at: $OUT" >&2
	exit 1
fi

# --- Install and launch ------------------------------------------------------

echo "Installing on $SERIAL ..."
INSTALL_OUT="$("$ADB" -s "$SERIAL" install -r "$OUT" 2>&1)" || true
printf '%s\n' "$INSTALL_OUT" | tail -3
if ! printf '%s' "$INSTALL_OUT" | grep -q "Success"; then
	echo "Install failed on $SERIAL (see the message above)." >&2
	echo "The APK is ready at: $OUT" >&2
	exit 1
fi

PACKAGE="$(
	sed -n 's/^package\/unique_name="\(.*\)".*$/\1/p' "$ROOT/export_presets.cfg" | head -1
)"
PACKAGE="${PACKAGE:-com.skyduel.game}"
ACTIVITY="$PACKAGE/com.godot.game.GodotAppLauncher"

echo "Launching $PACKAGE ..."
LAUNCH_OUT="$("$ADB" -s "$SERIAL" shell am start -W -n "$ACTIVITY" 2>&1)" || true
case "$LAUNCH_OUT" in
	*Error*|*Exception*)
		printf '%s\n' "$LAUNCH_OUT" | tail -5 >&2
		echo "The game was installed but would not start on $SERIAL." >&2
		exit 1
		;;
esac

echo "Running on $SERIAL: $PACKAGE"
