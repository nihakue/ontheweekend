#!/bin/bash
# Stream a show to icecast via ffmpeg
# Usage: stream-show.sh <file-path>
# Example: stream-show.sh /var/lib/radio/shows/saturday-2025-02-01.mp3

set -euo pipefail

SHOW_FILE="${1:-}"

# Icecast connection details (from environment or defaults)
ICECAST_HOST="${ICECAST_HOST:-localhost}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/stream}"
ICECAST_PASSWORD="${SOURCE_PASSWORD:-}"

if [[ -z "$SHOW_FILE" ]]; then
    echo "Usage: $0 <file-path>" >&2
    exit 1
fi

if [[ ! -f "$SHOW_FILE" ]]; then
    echo "Error: File not found: $SHOW_FILE" >&2
    exit 1
fi

if [[ -z "$ICECAST_PASSWORD" ]]; then
    echo "Error: SOURCE_PASSWORD environment variable required" >&2
    exit 1
fi

echo "Streaming: $SHOW_FILE"
echo "To: icecast://${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"

# Stream to icecast using ffmpeg
# -re: read input at native frame rate (real-time)
# -i: input file
# -acodec libmp3lame: encode as MP3
# -ab 192k: bitrate
# -f mp3: output format
# -content_type audio/mpeg: icecast content type
ffmpeg -re -i "$SHOW_FILE" \
    -ar 48000 -ac 2 \
    -acodec libmp3lame -ab 192k \
    -f mp3 -content_type audio/mpeg \
    "icecast://source:${ICECAST_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"

echo "Stream finished"
