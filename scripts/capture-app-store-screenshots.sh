#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly PROJECT_PATH="${WITT_PROJECT_PATH:-${REPO_ROOT}/witt.xcodeproj}"
readonly SCHEME="${WITT_SCHEME:-witt}"
readonly CONFIGURATION="${WITT_CONFIGURATION:-Debug}"
readonly BUNDLE_ID="${WITT_BUNDLE_ID:-in.sids.witt}"
readonly SIMULATOR_UDID="${WITT_SIMULATOR_UDID:-}"
readonly DERIVED_DATA="${WITT_DERIVED_DATA:-${TMPDIR:-/tmp}/witt-app-store-screenshots/DerivedData}"
readonly OUTPUT_ROOT="${WITT_OUTPUT_DIR:-${TMPDIR:-/tmp}/witt-app-store-screenshots/Captures}"
readonly CAPTURE_DELAY="${WITT_CAPTURE_DELAY:-2}"
readonly APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphonesimulator/witt.app"

usage() {
    cat <<'EOF'
Usage: scripts/capture-app-store-screenshots.sh <command> [arguments]

Commands:
  devices                  List available Simulator devices.
  demos                    List supported debug demo presets.
  build                    Build WITT for the selected booted Simulator.
  install                  Install the existing build without removing app data.
  launch [-- <arguments>]  Launch WITT, optionally with explicit app arguments.
  capture <name>           Capture the current Simulator screen as a new PNG.
  demo <preset> [name]     Launch a debug preset, wait, and capture it.

Required for all commands except devices and demos:
  WITT_SIMULATOR_UDID      UDID of an already booted Simulator.

Optional environment:
  WITT_DERIVED_DATA        DerivedData directory (defaults under TMPDIR).
  WITT_OUTPUT_DIR          Capture root (defaults under TMPDIR).
  WITT_CAPTURE_DELAY       Seconds to wait before a demo capture (default: 2).
  WITT_CONFIGURATION       Build configuration (default: Debug).

This script never erases a Simulator, uninstalls WITT, resets privacy settings,
creates fixture records, or submits App Store metadata.
EOF
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_udid() {
    require_command xcrun
    [[ -n "${SIMULATOR_UDID}" ]] || fail "set WITT_SIMULATOR_UDID to an already booted Simulator UDID"
    xcrun simctl getenv "${SIMULATOR_UDID}" HOME >/dev/null 2>&1 \
        || fail "Simulator ${SIMULATOR_UDID} is unavailable or not booted"
}

require_debug() {
    [[ "${CONFIGURATION}" == "Debug" ]] \
        || fail "debug demo launch arguments require WITT_CONFIGURATION=Debug"
}

require_app() {
    [[ -d "${APP_PATH}" ]] \
        || fail "app not found at ${APP_PATH}; run the build command first"
}

list_demos() {
    cat <<'EOF'
attach              Unknown-QR attachment sheet
camera-denied       Camera capture permission recovery
camera-restricted   Camera capture restricted state
create-attach       Create-and-attach sheet
known               Known-QR Add Thing flow; requires an existing destination
repair              Repair QR sheet; richer with two or more fixture targets
review              Review Thing sheet; requires an existing destination
scanner-denied      QR scanner permission recovery
scanner-restricted  QR scanner restricted state
EOF
}

demo_arguments() {
    case "$1" in
        attach) printf '%s\n' '--demo-unknown-qr' ;;
        camera-denied) printf '%s\n' '--demo-camera-capture' '--demo-camera-denied' ;;
        camera-restricted) printf '%s\n' '--demo-camera-capture' '--demo-camera-restricted' ;;
        create-attach) printf '%s\n' '--demo-create-attach' ;;
        known) printf '%s\n' '--demo-known-qr' ;;
        repair) printf '%s\n' '--demo-repair-qr' ;;
        review) printf '%s\n' '--demo-review-thing' ;;
        scanner-denied) printf '%s\n' '--demo-qr-scanner' '--demo-camera-denied' ;;
        scanner-restricted) printf '%s\n' '--demo-qr-scanner' '--demo-camera-restricted' ;;
        *) fail "unknown demo preset '$1'; run the demos command for valid names" ;;
    esac
}

sanitize_name() {
    local value="$1"
    value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
    value="${value#-}"
    value="${value%-}"
    [[ -n "${value}" ]] || fail "capture name must contain at least one letter or number"
    printf '%s\n' "${value}"
}

capture_screen() {
    local requested_name="$1"
    local safe_name
    local run_directory
    local output_path

    safe_name="$(sanitize_name "${requested_name}")"
    run_directory="${OUTPUT_ROOT}/$(date -u '+%Y%m%dT%H%M%SZ')"
    mkdir -p "${run_directory}"
    output_path="${run_directory}/${safe_name}.png"
    [[ ! -e "${output_path}" ]] || fail "refusing to overwrite ${output_path}"

    xcrun simctl io "${SIMULATOR_UDID}" screenshot --type=png "${output_path}"
    printf '%s\n' "${output_path}"
}

launch_app() {
    xcrun simctl launch --terminate-running-process \
        "${SIMULATOR_UDID}" "${BUNDLE_ID}" "$@"
}

main() {
    local command="${1:-}"
    case "${command}" in
        devices)
            require_command xcrun
            xcrun simctl list devices available
            ;;
        demos)
            list_demos
            ;;
        build)
            require_udid
            require_command xcodebuild
            xcodebuild \
                -project "${PROJECT_PATH}" \
                -scheme "${SCHEME}" \
                -configuration "${CONFIGURATION}" \
                -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}" \
                -derivedDataPath "${DERIVED_DATA}" \
                build
            printf 'Built %s\n' "${APP_PATH}"
            ;;
        install)
            require_udid
            require_app
            xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}"
            printf 'Installed %s without removing existing app data.\n' "${BUNDLE_ID}"
            ;;
        launch)
            require_udid
            shift
            if [[ "${1:-}" == "--" ]]; then
                shift
            fi
            launch_app "$@"
            ;;
        capture)
            require_udid
            [[ $# -eq 2 ]] || fail "capture requires exactly one name"
            capture_screen "$2"
            ;;
        demo)
            require_udid
            require_debug
            [[ $# -ge 2 && $# -le 3 ]] || fail "demo requires a preset and optional capture name"
            local preset="$2"
            local capture_name="${3:-${preset}}"
            local -a arguments=()
            while IFS= read -r argument; do
                arguments+=("${argument}")
            done < <(demo_arguments "${preset}")
            launch_app "${arguments[@]}"
            sleep "${CAPTURE_DELAY}"
            capture_screen "${capture_name}"
            ;;
        help|-h|--help|'')
            usage
            ;;
        *)
            usage >&2
            fail "unknown command '${command}'"
            ;;
    esac
}

main "$@"
