#!/usr/bin/env bash

set -euf -o pipefail

# Install/update
apt-get -y update
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" install icecast2

# Enable
cat >/etc/default/icecast2 <<'EOT'
${ICECAST_DEFAULT}
EOT

# Update config
cat >/etc/icecast2/icecast.xml <<'EOT'
${ICECAST_CONFIG_XML}
EOT

# Increase file limit
ex -s -c '2i|ulimit -n 10240' -c x /etc/init.d/icecast2

git clone https://github.com/nihakue/ontheweekend.git
cp ./ontheweekend/silence_* /usr/share/icecast2/web/

# Start icecast
/etc/init.d/icecast2 start
sleep 1
/etc/init.d/icecast2 restart

# Install scheduler dependencies
apt-get -y install ffmpeg

# Setup scheduler directories and scripts
mkdir -p /var/lib/radio/shows
cp ./ontheweekend/scheduler/stream-show.sh /usr/local/bin/
chmod +x /usr/local/bin/stream-show.sh

# Install pre-built scheduler binary (or build if Go available)
if [[ -f ./ontheweekend/scheduler/radio-scheduler ]]; then
    cp ./ontheweekend/scheduler/radio-scheduler /usr/local/bin/
else
    apt-get -y install golang-go
    cd ./ontheweekend/scheduler && CGO_ENABLED=0 go build -o /usr/local/bin/radio-scheduler . && cd -
fi

# Install systemd unit for scheduler web UI
cp ./ontheweekend/scheduler/systemd/radio-scheduler.service /etc/systemd/system/

# Create scheduler environment file
cat >/etc/radio-scheduler.env <<'EOT'
TZ=${TIMEZONE}
SATURDAY_TIME=${SATURDAY_TIME}
SUNDAY_TIME=${SUNDAY_TIME}
ICECAST_HOST=localhost
ICECAST_PORT=8000
ICECAST_MOUNT=/stream
SOURCE_PASSWORD=${SOURCE_PASSWORD}
SHOWS_DIR=/var/lib/radio/shows
LISTEN_ADDR=127.0.0.1:8080
EOT

# Enable and start scheduler
systemctl daemon-reload
systemctl enable --now radio-scheduler.service

# Install caddy
apt-get -y install debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get -y update
apt-get -y install caddy

# Configure caddy with scheduler
cat >/etc/caddy/Caddyfile <<'EOT'
${DOMAIN} {
	# Schedule UI - password protected
	handle /schedule* {
		basicauth {
			${SCHEDULE_USER} ${SCHEDULE_PASSWORD_HASH}
		}
		uri strip_prefix /schedule
		reverse_proxy localhost:8080
	}

	# Icecast stream
	handle {
		reverse_proxy localhost:8000
	}
}
EOT
systemctl reload caddy

# Open firewall ports (if not already open)
iptables -C INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT 5 -m state --state NEW -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT 5 -m state --state NEW -p tcp --dport 443 -j ACCEPT
netfilter-persistent save