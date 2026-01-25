#!/usr/bin/env bash
set -euf -o pipefail

# End-to-end test for Icecast streaming
# Generates a test tone, streams it to Icecast, and optionally plays it back

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
LISTEN=false
DURATION=15
FREQUENCY=440

while [[ $# -gt 0 ]]; do
    case $1 in
        --listen|-l)
            LISTEN=true
            shift
            ;;
        --duration|-d)
            DURATION="$2"
            shift 2
            ;;
        --frequency|-f)
            FREQUENCY="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --listen, -l        Also play back from stream (end-to-end test)"
            echo "  --duration, -d N    Duration in seconds (default: 15)"
            echo "  --frequency, -f N   Tone frequency in Hz (default: 440)"
            echo "  --help, -h          Show this help"
            exit 0
            ;;
        *)
            # Legacy positional args: duration, frequency
            if [[ -z "${DURATION_SET:-}" ]]; then
                DURATION="$1"
                DURATION_SET=1
            else
                FREQUENCY="$1"
            fi
            shift
            ;;
    esac
done

# Load passwords from .env
if [[ -f .env ]]; then
    source .env
else
    echo "Error: .env file not found. Create it with SOURCE_PASSWORD=yourpassword"
    exit 1
fi

if [[ -z "${SOURCE_PASSWORD:-}" ]]; then
    echo "Error: SOURCE_PASSWORD not set in .env"
    exit 1
fi

# Configuration
HOST="${ICECAST_HOST:-34.250.6.15}"
PORT="${ICECAST_PORT:-8000}"
MOUNT="${ICECAST_MOUNT:-/stream}"

STREAM_URL="icecast://source:${SOURCE_PASSWORD}@${HOST}:${PORT}${MOUNT}"
LISTEN_URL="http://${HOST}:${PORT}${MOUNT}"

echo "=== Icecast End-to-End Test ==="
echo "Host: ${HOST}:${PORT}"
echo "Mount: ${MOUNT}"
echo "Duration: ${DURATION}s"
echo "Frequency: ${FREQUENCY}Hz"
echo "Listen mode: ${LISTEN}"
echo ""

# Check for ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg not found. Please install ffmpeg."
    exit 1
fi

# Check for ffplay if listen mode
if [[ "$LISTEN" == "true" ]] && ! command -v ffplay &> /dev/null; then
    echo "Error: ffplay not found. Please install ffmpeg (includes ffplay)."
    exit 1
fi

echo "Streaming test tone to ${HOST}:${PORT}${MOUNT}..."
echo "Listen URL: ${LISTEN_URL}"
echo ""

STREAM_PID=""
PLAY_PID=""

cleanup() {
    # Kill background jobs on exit
    [[ -n "$STREAM_PID" ]] && kill $STREAM_PID 2>/dev/null || true
    [[ -n "$PLAY_PID" ]] && kill $PLAY_PID 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$LISTEN" == "true" ]]; then
    # Stream in background
    ffmpeg -re -f lavfi -i "sine=frequency=${FREQUENCY}:duration=${DURATION}" \
        -acodec libmp3lame -ab 128k \
        -f mp3 -content_type audio/mpeg \
        "${STREAM_URL}" 2>/dev/null &
    STREAM_PID=$!

    # Wait for stream to establish
    sleep 2

    echo "Playing back from stream..."
    # Calculate playback duration (stream duration minus startup delay)
    PLAY_DURATION=$((DURATION - 3))
    if [[ $PLAY_DURATION -lt 3 ]]; then
        PLAY_DURATION=3
    fi

    # Play with time limit - ffplay -t limits playback duration
    ffplay -nodisp -autoexit -t "${PLAY_DURATION}" "${LISTEN_URL}" 2>/dev/null &
    PLAY_PID=$!

    # Wait for stream to finish (this is the limiting factor)
    wait $STREAM_PID 2>/dev/null || true

    # Give playback a moment to finish, then kill it
    sleep 1
    kill $PLAY_PID 2>/dev/null || true
else
    # Just stream, no playback
    ffmpeg -re -f lavfi -i "sine=frequency=${FREQUENCY}:duration=${DURATION}" \
        -acodec libmp3lame -ab 128k \
        -f mp3 -content_type audio/mpeg \
        "${STREAM_URL}" 2>&1 | grep -v "^  " || true
fi

echo ""
echo "=== Test Complete ==="
echo "Check Icecast logs: tail /var/log/icecast2/error.log"
