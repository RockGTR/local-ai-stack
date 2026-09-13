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
chat_host=$(local_ai_validate_chat_url)

tailscale_bin=$(command -v tailscale || true)
if [ -z "$tailscale_bin" ]; then
  printf 'ERROR: tailscale CLI is not on PATH.\n' >&2
  exit 1
fi

tmp_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/local-ai-mac.XXXXXX")
cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

printf 'Checking Tailscale peer reachability...\n'
"$tailscale_bin" ping --c 1 --timeout 8s "$chat_host" >/dev/null

resolved_ip=$(/usr/bin/dscacheutil -q host -a name "$chat_host" | /usr/bin/awk '/ip_address:/ { print $2; exit }')
if [ -z "$resolved_ip" ]; then
  printf 'ERROR: MagicDNS did not resolve the configured chat hostname.\n' >&2
  exit 1
fi
printf 'PASS: MagicDNS resolved the Windows peer.\n'

curl_result=$(
  /usr/bin/curl \
    --proto '=https' \
    --tlsv1.2 \
    --connect-timeout 10 \
    --max-time 30 \
    --silent \
    --show-error \
    --location \
    --max-redirs 5 \
    --output "$tmp_dir/chat.html" \
    --write-out '%{http_code}|%{remote_ip}|%{ssl_verify_result}' \
    "$WINDOWS_CHAT_URL"
)

http_code=${curl_result%%|*}
curl_rest=${curl_result#*|}
remote_ip=${curl_rest%%|*}
ssl_verify_result=${curl_rest##*|}

if [ "$http_code" != 200 ]; then
  printf 'ERROR: chat route returned HTTP %s.\n' "$http_code" >&2
  exit 1
fi
if [ "$ssl_verify_result" != 0 ]; then
  printf 'ERROR: TLS certificate verification failed with code %s.\n' "$ssl_verify_result" >&2
  exit 1
fi

self_ip=$("$tailscale_bin" ip -4 2>/dev/null | /usr/bin/awk 'NR == 1 { print; exit }')
if [ -n "$self_ip" ] && [ "$remote_ip" = "$self_ip" ]; then
  printf 'ERROR: the configured route resolved back to this Mac.\n' >&2
  exit 1
fi
if [ "$remote_ip" != "$resolved_ip" ]; then
  printf 'ERROR: HTTPS reached an address different from the MagicDNS result.\n' >&2
  exit 1
fi
printf 'PASS: private HTTPS returned HTTP 200 with a valid certificate.\n'

config_url=${WINDOWS_CHAT_URL%/}/api/config
/usr/bin/curl \
  --proto '=https' \
  --tlsv1.2 \
  --connect-timeout 10 \
  --max-time 30 \
  --silent \
  --show-error \
  --fail \
  --output "$tmp_dir/open-webui-config.json" \
  "$config_url"

/usr/bin/python3 - "$tmp_dir/open-webui-config.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

if config.get("name") != "Open WebUI":
    raise SystemExit("ERROR: the HTTPS route did not identify Open WebUI.")
if config.get("features", {}).get("enable_signup") is not False:
    raise SystemExit("ERROR: Open WebUI signup is not confirmed disabled.")

version = config.get("version", "unknown")
print(f"PASS: Open WebUI {version} is reachable and public signup is disabled.")
PY

printf 'READY: browser chat route passed non-authenticated Mac checks.\n'
printf 'NEXT: open the route and complete an authenticated small chat interactively.\n'
