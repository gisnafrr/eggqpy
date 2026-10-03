# eggqpy

Custom Pterodactyl runtime image for Qoupay.

## Runtime & packages

- Bun
- Python
- Node.js (switchable with `NODE_VERSION`)
- FFmpeg
- Golang
- Redis
- MariaDB client
- PM2
- PNPM
- Speedtest CLI
- Nodemon
- Chromium
- yt-dlp
- Playwright
- Cloudflare Tunnel
- Git

## Features

- GitHub auto-update on every container start/restart
- Automatic dependency refresh when `package.json` / lockfile changes
- Colored Qoupay runtime dashboard
- Git branch and commit status on startup

## Docker image

```
ghcr.io/gisnafrr/eggqpy:main
```

## Pterodactyl egg

Use the new `egg-qoupay-ultimate-runtime.json` file.