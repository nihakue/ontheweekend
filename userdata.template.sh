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

# Start icecast
/etc/init.d/icecast2 start
sleep 1
/etc/init.d/icecast2 restart

# Install scheduler dependencies
apt-get -y install ffmpeg golang-go

# Create scheduler environment file (before install.sh so it doesn't use defaults)
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

# Run the scheduler install script
./ontheweekend/scheduler/install.sh

# Install caddy
apt-get -y install debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get -y update
apt-get -y install caddy

# Configure caddy with scheduler
cat >/etc/caddy/Caddyfile <<'EOT'
${HOST} {
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
# Some sources, like edcast, don't support https, so we expose 8000 so that caddy can redirect http to https on port 80
iptables -C INPUT -m state --state NEW -p tcp --dport 8000 -j ACCEPT 2>/dev/null || iptables -I INPUT 5 -m state --state NEW -p tcp --dport 8000 -j ACCEPT
netfilter-persistent save