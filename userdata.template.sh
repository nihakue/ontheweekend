#!/usr/bin/env bash

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

# Start server
/etc/init.d/icecast2 start
sleep 1
/etc/init.d/icecast2 restart