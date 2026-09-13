#!/bin/bash

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/mac-client-config.sh
. "$script_dir/lib/mac-client-config.sh"

usage() {
  printf 'Usage: %s [--config <private-env-file>]\n' "$0"
}

parse_status=0
local_ai_parse_config_arg "$@" || parse_status=$?
if [ "$parse_status" -eq 64 ]; then
  usage
  exit 0
elif [ "$parse_status" -ne 0 ]; then
  usage >&2
  exit "$parse_status"
fi

local_ai_read_chat_url "$config_file"
local_ai_validate_chat_url >/dev/null

/usr/bin/open "$WINDOWS_CHAT_URL"
printf 'Opened the private Open WebUI route in the default browser.\n'
