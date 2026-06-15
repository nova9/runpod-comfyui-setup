# ComfyUI model fetcher for RunPod

ComfyUI is already installed on the pod — this just pulls your models so you
don't have to SSH in and `wget` them by hand every time.

## Use it

Repo: <https://github.com/nova9/runpod-comfyui-setup>

On a fresh pod (in the web terminal or over SSH), clone and run — this gets
both `setup.sh` and `models.txt`:

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
2. Install `aria2` if missing (fast multi-connection downloads).
3. Prompt for your **Civitai** and **Hugging Face** tokens (cached at `~/.comfy-keys`, so it only asks once).
4. Download everything in [`models.txt`](models.txt) into `ComfyUI/models/<folder>`.

Already-downloaded files are skipped, so it's safe to re-run.

When run via `curl | bash` there's no `models.txt` on disk — clone the repo
instead, or set `MODELS_MANIFEST=/path/to/models.txt`.

## Adding models

Edit [`models.txt`](models.txt). One model per line, `|`-separated:

```text
folder | filename | url
```

- `folder` — subdir under `ComfyUI/models/` (`checkpoints`, `loras`, `upscale_models`, `vae`, …)
- `url` — the download URL **without** the token. Civitai gets `?token=` appended;
  Hugging Face gets an `Authorization: Bearer` header. Both come from the keys you enter.

## Options

```bash
COMFYUI_DIR=/ComfyUI ./setup.sh        # force the ComfyUI path
MODELS_MANIFEST=./other.txt ./setup.sh # use a different manifest
CIVITAI_TOKEN=xxx HF_TOKEN=yyy ./setup.sh  # non-interactive (CI / no TTY)
```

## Security

Tokens are entered at runtime and cached only in `~/.comfy-keys` (chmod 600,
gitignored). **Do not** hardcode tokens in `models.txt` or commit `~/.comfy-keys`.
