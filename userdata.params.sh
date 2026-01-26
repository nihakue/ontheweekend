set -euf -o pipefail

[[ -f .env ]] && source .env

ICECAST_CONFIG_XML=$(./template.sh ./icecast.template.xml ./icecast.params.sh)
ICECAST_DEFAULT=$(cat ./icecast2_defaults.sh)
SILENCE_BASE64=$(base64 ./silence_stereo_192.mp3)
DOMAIN=${DOMAIN:-}