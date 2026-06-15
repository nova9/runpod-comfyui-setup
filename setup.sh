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

SCRIPT_VERSION="2026-06-15.5"   # bump on changes so we can confirm which copy ran
# DEBUG=1 turns on bash xtrace for full step-by-step output.
[ "${DEBUG:-0}" = "1" ] && set -x
dbg() { echo -e "\033[0;90m[debug] $*\033[0m"; }

# ----------------------------------------------------------------------------
# Config (override with env vars, e.g. COMFYUI_DIR=/ComfyUI ./setup.sh)
# ----------------------------------------------------------------------------
COMFYUI_DIR="${COMFYUI_DIR:-}"          # auto-detected if empty
MODELS_MANIFEST="${MODELS_MANIFEST:-}"  # defaults to models.txt next to this script
# When run via `curl | bash` there's no local models.txt, so fetch it from here.
MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/nova9/runpod-comfyui-setup/main/models.txt}"
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
  dbg "find_comfyui: COMFYUI_DIR='${COMFYUI_DIR}'"
  [ -n "$COMFYUI_DIR" ] && { [ -d "$COMFYUI_DIR/models" ] || die "No models/ in $COMFYUI_DIR"; ok "ComfyUI: $COMFYUI_DIR"; return; }
  local c root
  for c in /workspace/ComfyUI /workspace/runpod-slim/ComfyUI /ComfyUI /root/ComfyUI \
           "$HOME/ComfyUI" /workspace/madapps/ComfyUI /opt/ComfyUI /app/ComfyUI; do
    dbg "checking $c/models"
    [ -d "$c/models" ] && { COMFYUI_DIR="$c"; ok "Found ComfyUI: $c"; return; }
  done
  # Deeper search of likely roots. `|| true` keeps SIGPIPE from head -1 (with
  # pipefail) from aborting the whole script under set -e.
  log "Searching for ComfyUI…"
  for root in /workspace /root /opt /app /home /; do
    [ -d "$root" ] || continue
    c="$(find "$root" -maxdepth 4 -type d -name models -path '*ComfyUI*' 2>/dev/null | head -1 || true)"
    [ -n "$c" ] && [ -d "$c" ] && { COMFYUI_DIR="$(dirname "$c")"; ok "Found ComfyUI: $COMFYUI_DIR"; return; }
    [ "$root" = / ] && break  # don't scan all of / twice
  done
  die "Could not find ComfyUI. Re-run with the path:  COMFYUI_DIR=/path/to/ComfyUI bash setup.sh"
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

  # Where to read interactive input. Under `curl | bash`, stdin is the script
  # pipe, so prompt from the controlling terminal instead.
  local src=""
  if [ -r /dev/tty ]; then src=/dev/tty; elif [ -t 0 ]; then src=/dev/stdin; fi

  if [ -z "$CIVITAI_TOKEN" ]; then
    if [ -n "$src" ]; then read -rsp "$(echo -e "${c_yellow}?${c_off}") Civitai API token (Enter to skip): " CIVITAI_TOKEN < "$src"; echo
    else warn "No terminal / no CIVITAI_TOKEN — Civitai downloads will be skipped"; fi
  fi
  if [ -z "$HF_TOKEN" ]; then
    if [ -n "$src" ]; then read -rsp "$(echo -e "${c_yellow}?${c_off}") Hugging Face token (Enter to skip): " HF_TOKEN < "$src"; echo
    else warn "No terminal / no HF_TOKEN — gated HF downloads may fail"; fi
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
  # No local manifest (running via curl|bash): fetch it from the repo.
  local tmp="${TMPDIR:-/tmp}/comfy-models.txt"
  curl -fsSL "$MANIFEST_URL" -o "$tmp" 2>/dev/null && [ -s "$tmp" ] && { echo "$tmp"; return; }
  echo ""
}

download_one() {
  local folder="$1" filename="$2" url="$3"
  local dest_dir="$COMFYUI_DIR/models/$folder" dest
  dest="$dest_dir/$filename"
  mkdir -p "$dest_dir"
  [ -s "$dest" ] && { ok "exists: $folder/$filename"; return; }

  local -a args=(--console-log-level=warn -k1M --continue=true
                 --auto-file-renaming=false --allow-overwrite=true
                 -d "$dest_dir" -o "$filename")

  if [[ "$url" == *civitai.com* || "$url" == *civitai.red* ]]; then
    [ -z "$CIVITAI_TOKEN" ] && { warn "skip (no Civitai token): $filename"; return; }
    if [[ "$url" == *\?* ]]; then url="${url}&token=${CIVITAI_TOKEN}"; else url="${url}?token=${CIVITAI_TOKEN}"; fi
    # Civitai's signed b2 URLs are single-shot — parallel range requests 403.
    # One connection only (still resumable). Slower, but it actually works.
    args+=(-x1 -s1 --max-connection-per-server=1)
  else
    args+=(-x16 -s16)
    if [[ "$url" == *huggingface.co* ]] && [ -n "$HF_TOKEN" ]; then
      args+=(--header="Authorization: Bearer ${HF_TOKEN}")
    fi
  fi

  log "downloading $folder/$filename"
  if aria2c "${args[@]}" "$url"; then ok "done: $folder/$filename"
  else warn "FAILED: $folder/$filename"; rm -f "$dest"; fi  # drop partial so re-run retries
}

# Strip leading/trailing whitespace without invoking xargs (which mangles
# quotes/apostrophes, e.g. "Vixon's").
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

download_models() {
  local manifest; manifest="$(resolve_manifest)"
  [ -z "$manifest" ] && die "No models.txt found next to setup.sh (or set MODELS_MANIFEST)"
  log "Manifest: $manifest"
  while IFS='|' read -r folder filename url || [ -n "$folder" ]; do
    folder="$(trim "$folder")"; filename="$(trim "$filename")"; url="$(trim "$url")"
    [ -z "$folder" ] && continue
    [[ "$folder" == \#* ]] && continue
    [ -z "$url" ] && { warn "bad line (no url): $folder $filename"; continue; }
    download_one "$folder" "$filename" "$url"
  done < "$manifest"
  ok "All models processed"
}

main() {
  echo -e "${c_green}ComfyUI model fetcher${c_off}  (version $SCRIPT_VERSION)"
  dbg "bash=$BASH_VERSION  pwd=$PWD  stdin-tty=$([ -t 0 ] && echo yes || echo no)  /dev/tty=$([ -r /dev/tty ] && echo readable || echo no)"
  dbg "step: find_comfyui";  find_comfyui
  dbg "step: ensure_aria2";  ensure_aria2
  dbg "step: load_keys";     load_keys
  dbg "step: download_models"; download_models
  log "Done. Restart ComfyUI (or use Manager → Refresh) to pick up new models."
}

main "$@"
