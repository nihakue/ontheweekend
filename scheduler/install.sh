#!/bin/bash
# Install the radio scheduler on the server
# Run this script on the target server (or via SSH)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing radio scheduler..."

# Create shows directory
mkdir -p /var/lib/radio/shows
chmod 755 /var/lib/radio/shows

# Install the stream script
cp "$SCRIPT_DIR/stream-show.sh" /usr/local/bin/stream-show.sh
chmod +x /usr/local/bin/stream-show.sh

# Build and install the Go binary (if Go is available)
if command -v go &>/dev/null; then
    echo "==> Building scheduler binary..."
    cd "$SCRIPT_DIR"
    CGO_ENABLED=0 go build -o /usr/local/bin/radio-scheduler .
else
    echo "==> Go not found, assuming binary already exists at /usr/local/bin/radio-scheduler"
fi

# Install systemd units
cp "$SCRIPT_DIR/systemd/radio-scheduler.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/radio-silence.service" /etc/systemd/system/

# Create environment file if it doesn't exist
if [[ ! -f /etc/radio-scheduler.env ]]; then
    cat >/etc/radio-scheduler.env <<'EOF'
# Radio scheduler configuration
# Edit this file and restart services to apply changes

# Timezone for show times
TZ=Europe/London

# Show times (24-hour format)
SATURDAY_TIME=18:00
SUNDAY_TIME=10:00

# Icecast connection
ICECAST_HOST=localhost
ICECAST_PORT=8000
ICECAST_MOUNT=/stream
SOURCE_PASSWORD=changeme

# Web UI
SHOWS_DIR=/var/lib/radio/shows
LISTEN_ADDR=127.0.0.1:8080
EOF
    echo "==> Created /etc/radio-scheduler.env - edit this file to configure!"
fi

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable --now radio-scheduler.service
systemctl enable --now radio-silence.service

echo "==> Installation complete!"
echo ""
echo "Service status:"
echo "  systemctl status radio-scheduler"
echo ""
echo "Configuration: /etc/radio-scheduler.env"
echo "Shows directory: /var/lib/radio/shows"
echo ""
echo "Don't forget to:"
echo "  1. Edit /etc/radio-scheduler.env with your SOURCE_PASSWORD"
echo "  2. Update Caddy config to proxy /schedule to localhost:8080"
