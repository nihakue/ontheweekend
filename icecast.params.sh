set -euf -o pipefail

if [[ ! $SOURCE_PASSWORD ]]; then
  SOURCE_PASSWORD=$RANDOM
fi

if [[ ! $RELAY_PASSWORD ]]; then
  RELAY_PASSWORD=$RANDOM
fi

if [[ ! $ADMIN_PASSWORD ]]; then
  ADMIN_PASSWORD=$RANDOM
fi

[[ -f .env ]] && source .env