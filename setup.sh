#!/usr/bin/env bash
#
# ComfyUI model fetcher for RunPod pods (ComfyUI is already installed).
#
# Prompts for API keys, then downloads every model in models.txt into the
# right ComfyUI/models/<folder>. Re-runnable: existing files are skipped.
#
# Quick start on a pod:
#   curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/setup.sh | bash
#
# Or clone the repo and run ./setup.sh

set -euo pipefail

# ----------------------------------------------------------------------------
# Config (override with env vars, e.g. COMFYUI_DIR=/ComfyUI ./setup.sh)
# ----------------------------------------------------------------------------
COMFYUI_DIR="${COMFYUI_DIR:-}"          # auto-detected if empty
MODELS_MANIFEST="${MODELS_MANIFEST:-}"  # defaults to models.txt next to this script
KEYS_FILE="${KEYS_FILE:-$HOME/.comfy-keys}"  # cached keys, lives OUTSIDE the repo

c_blue='\033[1;34m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_off='\033[0m'
log()  { echo -e "${c_blue}==>${c_off} $*"; }
ok()   { echo -e "${c_green}  ✓${c_off} $*"; }
warn() { echo -e "${c_yellow}  !${c_off} $*"; }
die()  { echo -e "${c_red}  ✗ $*${c_off}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "$PWD")"

# ----------------------------------------------------------------------------
# 1. Locate the existing ComfyUI install
# ----------------------------------------------------------------------------
find_comfyui() {
  [ -n "$COMFYUI_DIR" ] && { [ -d "$COMFYUI_DIR/models" ] || die "No models/ in $COMFYUI_DIR"; ok "ComfyUI: $COMFYUI_DIR"; return; }
  local c
  for c in /workspace/ComfyUI /ComfyUI /root/ComfyUI "$HOME/ComfyUI" /workspace/madapps/ComfyUI; do
    [ -d "$c/models" ] && { COMFYUI_DIR="$c"; ok "Found ComfyUI: $c"; return; }
  done
  # Last resort: search common roots.
  c="$(find /workspace / -maxdepth 4 -type d -name models -path '*ComfyUI*' 2>/dev/null | head -1)"
  [ -n "$c" ] && { COMFYUI_DIR="$(dirname "$c")"; ok "Found ComfyUI: $COMFYUI_DIR"; return; }
  die "Could not find ComfyUI. Set it explicitly: COMFYUI_DIR=/path/to/ComfyUI ./setup.sh"
}

# ----------------------------------------------------------------------------
# 2. aria2 (fast multi-connection downloader)
# ----------------------------------------------------------------------------
ensure_aria2() {
  command -v aria2c >/dev/null && return
  log "Installing aria2"
  if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq aria2
  else die "aria2c missing and apt-get unavailable — install aria2 manually"; fi
}

# ----------------------------------------------------------------------------
# 3. API keys (prompt once, cache for re-runs)
# ----------------------------------------------------------------------------
load_keys() {
  [ -f "$KEYS_FILE" ] && source "$KEYS_FILE"
  CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"; HF_TOKEN="${HF_TOKEN:-}"

  if [ -z "$CIVITAI_TOKEN" ]; then
    if [ -t 0 ]; then read -rsp "$(echo -e "${c_yellow}?${c_off}") Civitai API token (Enter to skip): " CIVITAI_TOKEN; echo
    else warn "No TTY / no CIVITAI_TOKEN — Civitai downloads will be skipped"; fi
  fi
  if [ -z "$HF_TOKEN" ]; then
    if [ -t 0 ]; then read -rsp "$(echo -e "${c_yellow}?${c_off}") Hugging Face token (Enter to skip): " HF_TOKEN; echo
    else warn "No TTY / no HF_TOKEN — gated HF downloads may fail"; fi
  fi

  umask 077
  printf 'CIVITAI_TOKEN="%s"\nHF_TOKEN="%s"\n' "$CIVITAI_TOKEN" "$HF_TOKEN" > "$KEYS_FILE"
  ok "Keys cached at $KEYS_FILE (chmod 600 — never commit this)"
}

# ----------------------------------------------------------------------------
# 4. Model downloads
# ----------------------------------------------------------------------------
resolve_manifest() {
  [ -n "$MODELS_MANIFEST" ] && [ -f "$MODELS_MANIFEST" ] && { echo "$MODELS_MANIFEST"; return; }
  [ -f "$SCRIPT_DIR/models.txt" ] && { echo "$SCRIPT_DIR/models.txt"; return; }
  echo ""
}

download_one() {
  local folder="$1" filename="$2" url="$3"
  local dest_dir="$COMFYUI_DIR/models/$folder" dest
  dest="$dest_dir/$filename"
  mkdir -p "$dest_dir"
  [ -s "$dest" ] && { ok "exists: $folder/$filename"; return; }

  local -a args=(--console-log-level=warn -x16 -s16 -k1M --continue=true
                 --auto-file-renaming=false --allow-overwrite=true
                 -d "$dest_dir" -o "$filename")

  if [[ "$url" == *civitai.com* || "$url" == *civitai.red* ]]; then
    [ -z "$CIVITAI_TOKEN" ] && { warn "skip (no Civitai token): $filename"; return; }
    if [[ "$url" == *\?* ]]; then url="${url}&token=${CIVITAI_TOKEN}"; else url="${url}?token=${CIVITAI_TOKEN}"; fi
  elif [[ "$url" == *huggingface.co* ]] && [ -n "$HF_TOKEN" ]; then
    args+=(--header="Authorization: Bearer ${HF_TOKEN}")
  fi

  log "downloading $folder/$filename"
  if aria2c "${args[@]}" "$url"; then ok "done: $folder/$filename"
  else warn "FAILED: $folder/$filename"; rm -f "$dest"; fi  # drop partial so re-run retries
}

download_models() {
  local manifest; manifest="$(resolve_manifest)"
  [ -z "$manifest" ] && die "No models.txt found next to setup.sh (or set MODELS_MANIFEST)"
  log "Manifest: $manifest"
  while IFS='|' read -r folder filename url || [ -n "$folder" ]; do
    folder="$(echo "$folder" | xargs)"; filename="$(echo "$filename" | xargs)"; url="$(echo "$url" | xargs)"
    [ -z "$folder" ] && continue
    [[ "$folder" == \#* ]] && continue
    [ -z "$url" ] && { warn "bad line (no url): $folder $filename"; continue; }
    download_one "$folder" "$filename" "$url"
  done < "$manifest"
  ok "All models processed"
}

main() {
  echo -e "${c_green}ComfyUI model fetcher${c_off}"
  find_comfyui
  ensure_aria2
  load_keys
  download_models
  log "Done. Restart ComfyUI (or use Manager → Refresh) to pick up new models."
}

main "$@"
