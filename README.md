# ComfyUI model fetcher for RunPod

ComfyUI is already installed on the pod — this just pulls your models so you
don't have to SSH in and `wget` them by hand every time.

## Use it

Repo: <https://github.com/nova9/runpod-comfyui-setup>

On a fresh pod (in the web terminal or over SSH), clone and run — this gets
both `setup.sh` and `models.json`:

```bash
git clone https://github.com/nova9/runpod-comfyui-setup && cd runpod-comfyui-setup && ./setup.sh
```

Or the raw one-liner (only fetches `setup.sh`, so set `MODELS_MANIFEST` or it
has nothing to download):

```bash
curl -fsSL https://raw.githubusercontent.com/nova9/runpod-comfyui-setup/main/setup.sh | bash
```

It will:

1. Find your ComfyUI install (`/workspace/ComfyUI`, `/ComfyUI`, … — auto-detected).
2. Install `aria2`, `wget`, and `jq` if missing (downloads + manifest parsing).
3. Prompt for your **Civitai** and **Hugging Face** tokens (cached at `~/.comfy-keys`, so it only asks once).
4. Download every enabled model in [`models.json`](models.json) into `ComfyUI/models/<folder>`.

Already-downloaded files are skipped, so it's safe to re-run.

When run via `curl | bash` there's no `models.json` on disk — clone the repo
instead, or set `MODELS_MANIFEST=/path/to/models.json`.

## Adding models

Edit [`models.json`](models.json). Add an object to the `models` array:

```json
{ "folder": "checkpoints", "filename": "my_model.safetensors", "url": "https://…", "enabled": true }
```

- `folder` — subdir under `ComfyUI/models/` (`checkpoints`, `loras`, `upscale_models`, `vae`, …)
- `url` — the download URL **without** the token. Civitai gets `?token=` appended;
  Hugging Face gets an `Authorization: Bearer` header. Both come from the keys you enter.
- `enabled` — set to `false` to skip a model without deleting it. Omit it and the
  model is downloaded by default. `section` is an optional label, ignored by the script.

## Options

```bash
COMFYUI_DIR=/ComfyUI ./setup.sh          # force the ComfyUI path
MODELS_MANIFEST=./other.json ./setup.sh  # use a different manifest
CIVITAI_TOKEN=xxx HF_TOKEN=yyy ./setup.sh  # non-interactive (CI / no TTY)
```

## Security

Tokens are entered at runtime and cached only in `~/.comfy-keys` (chmod 600,
gitignored). **Do not** hardcode tokens in `models.json` or commit `~/.comfy-keys`.
