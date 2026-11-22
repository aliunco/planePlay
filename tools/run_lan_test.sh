#!/usr/bin/env bash
# Starts two headless copies of the game over real UDP on localhost, has them
# play together, and checks that both simulations agree.
#
#   tools/run_lan_test.sh
set -uo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
# NOTE: not named PORT - some shells/CI images export PORT=0.
LAN_PORT="${LAN_PORT:-27791}"
cd "$(dirname "$0")/.." || exit 1

OUT_DIR="$(mktemp -d)"
SCENE="res://tools/lan_test.tscn"

"$GODOT" --headless --path . "$SCENE" -- --mode=host --port="$LAN_PORT" \
  > "$OUT_DIR/host.log" 2>&1 &
HOST_PID=$!

sleep 3

"$GODOT" --headless --path . "$SCENE" -- --mode=join --address=127.0.0.1 --port="$LAN_PORT" \
  > "$OUT_DIR/client.log" 2>&1 &
CLIENT_PID=$!

wait $HOST_PID
HOST_STATUS=$?
wait $CLIENT_PID
CLIENT_STATUS=$?

echo "--- host (exit $HOST_STATUS) ---"
grep -E "PASS|FAIL|LAN_TEST|LAN_RESULT|lan test finished" "$OUT_DIR/host.log"
echo "--- client (exit $CLIENT_STATUS) ---"
grep -E "PASS|FAIL|LAN_TEST|LAN_RESULT|lan test finished" "$OUT_DIR/client.log"

python3 - "$OUT_DIR/host.log" "$OUT_DIR/client.log" <<'PY'
import math
import re
import sys


def parse(path):
    text = open(path).read()
    match = re.search(
        r"LAN_RESULT role=(\w+) local=\(([-\d.]+), ([-\d.]+)\) "
        r"remote=\(([-\d.]+), ([-\d.]+)\) remote_rot=([-\d.]+).*?"
        r"health=(\d+)/(\d+) local_health=(\d+) "
        r"courier=\(([-\d.]+), ([-\d.]+)\) pickups=(\d+) "
        r"pickup0=\(([-\d.]+), ([-\d.]+)\) kind=(-?\d+)",
        text,
    )
    if not match:
        print("FAIL  no LAN_RESULT in", path)
        sys.exit(1)
    return {
        "role": match.group(1),
        "local": (float(match.group(2)), float(match.group(3))),
        "remote": (float(match.group(4)), float(match.group(5))),
        "remote_rot": float(match.group(6)),
        "remote_health": int(match.group(7)),
        "max_health": int(match.group(8)),
        "local_health": int(match.group(9)),
        "courier": (float(match.group(10)), float(match.group(11))),
        "pickups": int(match.group(12)),
        "pickup0": (float(match.group(13)), float(match.group(14))),
        "kind": int(match.group(15)),
    }


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


host = parse(sys.argv[1])
client = parse(sys.argv[2])
failures = 0

if {host["role"], client["role"]} != {"host", "join"}:
    print("FAIL  roles are wrong:", host["role"], client["role"])
    failures += 1
else:
    print("PASS  one process hosted and one joined")

for label, a, b in (
    ("host airplane matches on both screens", host["local"], client["remote"]),
    ("client airplane matches on both screens", host["remote"], client["local"]),
):
    gap = distance(a, b)
    if gap <= 25.0:
        print("PASS  %s (%.1f px apart)" % (label, gap))
    else:
        print("FAIL  %s (%.1f px apart)" % (label, gap))
        failures += 1

# Each device owns the airplane it flies. `remote_health` is what this device
# believes about the other pilot; `local_health` is its own. The two must agree,
# or one screen is showing a pilot the other has already damaged (or killed).
shared = sorted({host["local_health"], client["remote_health"], host["remote_health"], client["local_health"]})
if (
    host["local_health"] == client["remote_health"]
    and client["local_health"] == host["remote_health"]
    and host["local_health"] == host["max_health"] - 34
    and client["local_health"] == client["max_health"] - 34
):
    print(
        "PASS  both devices agree on both pilots' health (%d each after one hit)"
        % host["local_health"]
    )
else:
    print(
        "FAIL  the two devices disagree about health (host %d sees %d, client %d sees %d)"
        % (host["local_health"], host["remote_health"], client["local_health"], client["remote_health"])
    )
    failures += 1

if host["courier"] == (0.0, 0.0) or client["courier"] == (0.0, 0.0):
    print("FAIL  the courier never planned a pass")
    failures += 1
else:
    gap = distance(host["courier"], client["courier"])
    if gap <= 1.0:
        print("PASS  both devices planned the same courier drop (%.1f px apart)" % gap)
    else:
        print("FAIL  the two devices plan drops in different places (%.1f px apart)" % gap)
        failures += 1

if host["pickups"] > 0 and client["pickups"] > 0:
    gap = distance(host["pickup0"], client["pickup0"])
    if gap <= 1.0 and host["kind"] == client["kind"]:
        print("PASS  the dropped pickup is identical on both devices (%.1f px apart)" % gap)
    else:
        print(
            "FAIL  the dropped pickups differ (%.1f px apart, kind %d / %d)"
            % (gap, host["kind"], client["kind"])
        )
        failures += 1
else:
    print("note  no drop had been released yet on both devices (%d / %d in the air)" % (host["pickups"], client["pickups"]))

sys.exit(1 if failures else 0)
PY
COMPARE_STATUS=$?

rm -rf "$OUT_DIR"
if [ $HOST_STATUS -ne 0 ] || [ $CLIENT_STATUS -ne 0 ] || [ $COMPARE_STATUS -ne 0 ]; then
  echo "LAN test FAILED"
  exit 1
fi
echo "LAN test passed"
