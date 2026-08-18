#!/usr/bin/env bash

set -euo pipefail

SDK_ROOT="${ANDROID_SDK_ROOT:-/Users/willwang/Library/Android/sdk}"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR="$SDK_ROOT/emulator/emulator"

AVD_NAME="${AVD_NAME:-small}"
EMULATOR_PORT="${EMULATOR_PORT:-5554}"
SERIAL="emulator-$EMULATOR_PORT"
DROIDCAST_PORT="${DROIDCAST_PORT:-53516}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APK="${DROIDCAST_APK:-$SCRIPT_DIR/DroidCast_raw-release-1.1.apk}"
REMOTE_APK="/data/local/tmp/DroidCast_raw.apk"
EMULATOR_LOG="${TMPDIR:-/tmp}/droidcast-emulator-$AVD_NAME.log"
DROIDCAST_LOG="/data/local/tmp/droidcast_raw.log"
FORWARD_CREATED=0

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ "$FORWARD_CREATED" == "1" ]]; then
        "$ADB" -s "$SERIAL" forward --remove "tcp:$DROIDCAST_PORT" \
            >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT INT TERM

[[ -x "$ADB" ]] || die "ADB not found at $ADB"
[[ -x "$EMULATOR" ]] || die "Android Emulator not found at $EMULATOR"
[[ -f "$APK" ]] || die "DroidCast release APK not found at $APK"

"$ADB" start-server >/dev/null

if [[ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)" == "device" ]]; then
    running_avd="$(
        "$ADB" -s "$SERIAL" emu avd name 2>/dev/null \
            | tr -d '\r' \
            | sed -n '1p'
    )"
    [[ "$running_avd" == "$AVD_NAME" ]] || \
        die "$SERIAL is already occupied by AVD '$running_avd', not '$AVD_NAME'"
    printf 'AVD %s is already running as %s.\n' "$AVD_NAME" "$SERIAL"
else
    printf 'Starting AVD %s as %s...\n' "$AVD_NAME" "$SERIAL"
    nohup "$EMULATOR" \
        -avd "$AVD_NAME" \
        -port "$EMULATOR_PORT" \
        -gpu swangle \
        -feature GLESDynamicVersion \
        -no-snapshot \
        -netspeed full \
        -netdelay none \
        -dns-server 8.8.8.8,8.8.4.4 \
        >"$EMULATOR_LOG" 2>&1 &

    for _ in {1..120}; do
        if [[ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)" == "device" ]]; then
            break
        fi
        sleep 2
    done

    [[ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)" == "device" ]] || \
        die "Emulator did not connect within 4 minutes; see $EMULATOR_LOG"
fi

printf 'Waiting for Android to finish booting...\n'
for _ in {1..120}; do
    boot_completed="$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    [[ "$boot_completed" == "1" ]] && break
    sleep 2
done

[[ "${boot_completed:-}" == "1" ]] || \
    die "Android did not finish booting within 4 minutes; see $EMULATOR_LOG"

stale_pids="$(
    "$ADB" -s "$SERIAL" shell ps -A -o PID,ARGS 2>/dev/null \
        | awk 'index($0, "ink.mol.droidcast_raw.Main") { print $1 }' \
        | tr '\n' ' '
)"

if [[ -n "${stale_pids// }" ]]; then
    printf 'Stopping stale DroidCast process(es): %s\n' "$stale_pids"
    "$ADB" -s "$SERIAL" shell "kill $stale_pids" >/dev/null 2>&1 || true

    for _ in {1..10}; do
        remaining_pids="$(
            "$ADB" -s "$SERIAL" shell ps -A -o PID,ARGS 2>/dev/null \
                | awk 'index($0, "ink.mol.droidcast_raw.Main") { print $1 }'
        )"
        [[ -z "$remaining_pids" ]] && break
        sleep 1
    done

    [[ -z "${remaining_pids:-}" ]] || \
        die "The stale DroidCast process did not stop"
fi

printf 'Pushing DroidCast release APK...\n'
"$ADB" -s "$SERIAL" push "$APK" "$REMOTE_APK" >/dev/null

"$ADB" -s "$SERIAL" forward "tcp:$DROIDCAST_PORT" "tcp:$DROIDCAST_PORT" \
    >/dev/null
FORWARD_CREATED=1

printf 'Starting DroidCast on port %s...\n' "$DROIDCAST_PORT"
remote_command="LD_PRELOAD=/system/lib64/libandroid_servers.so CLASSPATH=$REMOTE_APK toybox nohup app_process / ink.mol.droidcast_raw.Main --port=$DROIDCAST_PORT >$DROIDCAST_LOG 2>&1 </dev/null &"
"$ADB" -s "$SERIAL" shell "$remote_command"

PREVIEW_URL="http://127.0.0.1:$DROIDCAST_PORT/preview"
for _ in {1..15}; do
    if curl -fsS --max-time 5 -o /dev/null "$PREVIEW_URL"; then
        printf '\nDroidCast is ready: %s\n' "$PREVIEW_URL"
        printf 'DroidCast is detached and will survive ADB reconnects.\n'
        printf 'Device log: %s\n\n' "$DROIDCAST_LOG"
        FORWARD_CREATED=0
        trap - EXIT INT TERM
        exit 0
    fi
    sleep 1
done

die "DroidCast started but $PREVIEW_URL did not become ready"
