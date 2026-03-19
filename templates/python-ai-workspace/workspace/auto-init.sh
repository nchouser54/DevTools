#!/usr/bin/env bash
set -euo pipefail

# Runs workspace initialization once per user unless explicitly forced.
: "${AUTO_SETUP_ON_LOGIN:=true}"
: "${FORCE_DEVTOOLS_INIT:=false}"

if [[ "${AUTO_SETUP_ON_LOGIN,,}" != "true" ]]; then
  exit 0
fi

marker_dir="${HOME}/.cache/devtools"
marker_file="${marker_dir}/init.done"
log_file="${marker_dir}/init.log"
mkdir -p "${marker_dir}"

if [[ -f "${marker_file}" && "${FORCE_DEVTOOLS_INIT,,}" != "true" ]]; then
  exit 0
fi

if [[ -x "/usr/local/bin/devtools-init-workspace" ]]; then
  /usr/local/bin/devtools-init-workspace >>"${log_file}" 2>&1 || true
fi

date -u +"%Y-%m-%dT%H:%M:%SZ" >"${marker_file}"
