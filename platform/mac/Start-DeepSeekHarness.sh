#!/bin/bash

set -euo pipefail
umask 077

dsh_version=0.1.5-rc.2
node_bin=${DSH_NODE_BIN:-/opt/homebrew/opt/node@22/bin/node}
runtime_root=${DSH_RUNTIME_ROOT:-$HOME/Library/Application Support/DeepSeek Harness/runtime/$dsh_version}
dsh_entry="$runtime_root/node_modules/@deepseek-ai/dsh/lib/bin.js"
dsh_home=${DSH_HOME:-$HOME/Library/Application Support/DeepSeek Harness/home}
workspace_root=${DSH_WORKSPACE:-$HOME/Documents/DeepSeek Harness Workspace}

for argument in "$@"; do
  case "$argument" in
    --host|--host=*)
      printf 'ERROR: this launcher fixes the Harness listener to 127.0.0.1.\n' >&2
      exit 2
      ;;
  esac
done

if [ ! -x "$node_bin" ]; then
  printf 'ERROR: compatible Node.js runtime is unavailable: %s\n' "$node_bin" >&2
  exit 1
fi

if [ ! -f "$dsh_entry" ]; then
  printf 'ERROR: pinned DeepSeek Harness %s is not installed.\n' "$dsh_version" >&2
  exit 1
fi

mkdir -p "$dsh_home" "$workspace_root"
chmod 700 "$dsh_home" "$workspace_root"
cd "$workspace_root"

export DSH_HOME="$dsh_home"
exec "$node_bin" "$dsh_entry" web --host 127.0.0.1 "$@"
