#!/bin/bash

local_ai_default_config() {
  printf '%s\n' "${LOCAL_AI_MAC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/local-ai-stack/mac-client.private.env}"
}

local_ai_read_chat_url() {
  config_file=$1

  if [ ! -r "$config_file" ]; then
    printf 'ERROR: private config is not readable: %s\n' "$config_file" >&2
    return 1
  fi

  /usr/bin/python3 - "$config_file" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
metadata = os.stat(path)
mode = stat.S_IMODE(metadata.st_mode)

if metadata.st_uid != os.getuid():
    raise SystemExit("ERROR: private config must be owned by the current user.")
if mode & 0o077:
    raise SystemExit("ERROR: private config must not be accessible by group or other users; run chmod 600.")
PY

  chat_url=$(
    /usr/bin/awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*WINDOWS_CHAT_URL[[:space:]]*=/ {
        sub(/^[^=]*=/, "")
        sub(/^[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        print
        exit
      }
    ' "$config_file"
  )

  case "$chat_url" in
    \"*\") chat_url=${chat_url#\"}; chat_url=${chat_url%\"} ;;
    \'*\') chat_url=${chat_url#\'}; chat_url=${chat_url%\'} ;;
  esac

  if [ -z "$chat_url" ] || [ "$chat_url" = '<WINDOWS_CHAT_URL>' ]; then
    printf 'ERROR: WINDOWS_CHAT_URL is not populated in the private config.\n' >&2
    return 1
  fi

  WINDOWS_CHAT_URL=$chat_url
  export WINDOWS_CHAT_URL
}

local_ai_validate_chat_url() {
  /usr/bin/python3 - "$WINDOWS_CHAT_URL" <<'PY'
import sys
from urllib.parse import urlsplit

value = sys.argv[1]
parsed = urlsplit(value)

if parsed.scheme != "https":
    raise SystemExit("ERROR: WINDOWS_CHAT_URL must use HTTPS.")
if not parsed.hostname:
    raise SystemExit("ERROR: WINDOWS_CHAT_URL must include a hostname.")
if not parsed.hostname.lower().endswith(".ts.net"):
    raise SystemExit("ERROR: WINDOWS_CHAT_URL must use a Tailscale Serve hostname ending in .ts.net.")
if parsed.port not in (None, 443):
    raise SystemExit("ERROR: WINDOWS_CHAT_URL must use the contracted HTTPS port 443.")
if parsed.username is not None or parsed.password is not None:
    raise SystemExit("ERROR: credentials must not be embedded in WINDOWS_CHAT_URL.")
if parsed.query or parsed.fragment:
    raise SystemExit("ERROR: WINDOWS_CHAT_URL must not contain a query or fragment.")

print(parsed.hostname)
PY
}

local_ai_parse_config_arg() {
  config_file=$(local_ai_default_config)

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --config)
        if [ "$#" -lt 2 ]; then
          printf 'ERROR: --config requires a path.\n' >&2
          return 2
        fi
        config_file=$2
        shift 2
        ;;
      -h|--help)
        return 64
        ;;
      *)
        printf 'ERROR: unknown argument: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done
}
