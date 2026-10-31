#!/bin/bash
set -euo pipefail
# Unix PipeStream caches its temporary namespace when PowerShell starts.
# Establish every worker environment path before starting a fresh process.
physical_temp=$(cd "$RUNNER_TEMP" && pwd -P)
validation_root=$(mktemp -d "$physical_temp/cfXXXXXXXX")
mkdir "$validation_root/tmp" "$validation_root/state" "$validation_root/xdg-config" "$validation_root/xdg-data" "$validation_root/xdg-cache" "$validation_root/xdg-state" "$validation_root/codex-empty"
export CF_VALIDATION_ROOT="$validation_root"
export TMPDIR="$validation_root/tmp"
export CONTROLFLOW_STATE_ROOT="$validation_root/state"
export XDG_CONFIG_HOME="$validation_root/xdg-config" XDG_DATA_HOME="$validation_root/xdg-data"
export XDG_CACHE_HOME="$validation_root/xdg-cache" XDG_STATE_HOME="$validation_root/xdg-state"
export CODEX_HOME="$validation_root/codex-empty"
exec pwsh -NoProfile -NonInteractive -File "$GITHUB_WORKSPACE/.validation/run-macos-validation.ps1"
