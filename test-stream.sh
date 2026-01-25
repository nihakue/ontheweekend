#\!/usr/bin/env bash
set -euf -o pipefail

# End-to-end test for Icecast streaming
# Generates a test tone, streams it to Icecast, and optionally plays it back

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
DURATION="${1:-15}"  # Default 15 seconds, or pass as first argument
FREQUENCY="${2:-440}" # Default 440Hz (A4), or pass as second argument

STREAM_URL="icecast://source:${SOURCE_PASSWORD}@${HOST}:${PORT}${MOUNT}"
LISTEN_URL="http://${HOST}:${PORT}${MOUNT}"

echo "=== Icecast End-to-End Test ==="
echo "Host: ${HOST}:${PORT}"
echo "Mount: ${MOUNT}"
echo "Duration: ${DURATION}s"
echo "Frequency: ${FREQUENCY}Hz"
echo ""

# Check for ffmpeg
if \! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg not found. Please install ffmpeg."
    exit 1
fi

echo "Streaming test tone to ${HOST}:${PORT}${MOUNT}..."
echo "Listen at: ${LISTEN_URL}"
echo ""

# Stream the test tone at realtime speed (-re flag)
ffmpeg -re -f lavfi -i "sine=frequency=${FREQUENCY}:duration=${DURATION}" \
    -acodec libmp3lame -ab 128k \
    -f mp3 -content_type audio/mpeg \
    "${STREAM_URL}" 2>&1 | grep -v "^  " || true

echo ""
echo "=== Test Complete ==="
echo "Check Icecast logs: tail /var/log/icecast2/error.log"
