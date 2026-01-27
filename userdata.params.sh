set -euf -o pipefail

[[ -f .env ]] && source .env

ICECAST_CONFIG_XML=$(./template.sh ./icecast.template.xml ./icecast.params.sh)
ICECAST_DEFAULT=$(cat ./icecast2_defaults.sh)
DOMAIN=${DOMAIN:-}