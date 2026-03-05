# OpenCode Safe Update Page

This page is published at `/safe/` and generates secure terminal commands for:

- `update` (backup + safe cleanup)
- `backup`
- `restore`
- `status`

It supports command generation for:

- Windows (PowerShell)
- macOS
- Linux

## Public Assets

The page depends on:

- `/scripts/opencode-safe.sh`
- `/scripts/opencode-safe.ps1`
- `/scripts/checksums.txt`
- `/scripts/manifest.json`

## Deploy On Vercel

Recommended setup:

1. Import this repository in Vercel.
2. Set the project root to `packages/app`.
3. Build command: `vite build`
4. Output directory: `dist`

After deploy, access:

- `https://<project>.vercel.app/safe/`
