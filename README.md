# local-dev-traefik-proxy

A minimal Traefik-based reverse proxy for local development.

This repo provides a shared HTTPS front-end and Docker network for multiple local projects, so each app can run at its own `*.test` domain without installing PHP/Node/etc. on the host.

## Goals

- **One proxy, many apps**: run multiple Laravel / Node / whatever projects in parallel.
- **Clean separation**: this repo is infra-only; apps live in their own repos.
- **HTTPS by default**: self-signed wildcard cert for `*.test`.
- **No host pollution**: only Docker and your editor on the host OS.

## How it works

- Starts a single Traefik container on ports `80` and `443`.
- Creates a shared Docker network called `web`.
- Uses a locally generated self-signed cert as the default TLS cert.
- Individual projects:
    - Attach their `web` (nginx) service to the `web` network.
    - Opt-in via Traefik labels.
    - Declare their own `myapp.test` (or similar) hostnames.

## Requirements

- Docker
- docker compose plugin (v2+)
- Linux host (tested on Linux Mint; works anywhere Docker does)

No PHP, no Node, no Composer required on the host.

## Setup

### 1. Clone this repo

```bash
mkdir -p ~/docker
cd ~/docker
git clone git@github.com:your-org/local-dev-traefik-proxy.git
cd local-dev-traefik-proxy
