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

1. Clone this repo
2. Generate the dev certificate

```bash
./scripts/generate-cert.sh
```

This creates:

* `certs/dev.crt`
* `certs/dev.key`

These files are not committed (see certs/.gitignore).

3. Trust the certificate (Linux Mint)

One-time step so browsers accept https://*.test:

```bash
sudo cp certs/dev.crt /usr/local/share/ca-certificates/local-dev-traefik.crt
sudo update-ca-certificates
```

4. Start Traefik

```bash
docker compose up -d
```

This:

* Runs Traefik on `80` and `443`.
* Creates the web network. 

You generally leave this running while you develop.

## Using with a project

In any project you want to expose via this proxy:

1. Add a domain to /etc/hosts:

```bash
127.0.0.1   myapp.test
```

2. In that project's `docker-compose.yml`, for the web (nginx) service:

* Attach to the shared web network:

```yaml
networks:
  - default
  - web
```

* Add Traefik labels:

```yaml
labels:
- "traefik.enable=true"
- "traefik.http.routers.myapp.rule=Host(`myapp.test`)"
- "traefik.http.routers.myapp.entrypoints=websecure"
- "traefik.http.routers.myapp.tls=true"
```

3. Declare the external network:
 
```yaml
networks:
  web:
    external: true
```

4. Bring the project up:

```bash
docker compose up -d
```

Now:

* https://myapp.test → that project's container.
* You can run multiple projects (foo.test, bar.test, etc.) in parallel, all via this shared proxy.

## Notes / Conventions

* This stack is dev-only. Do not use this cert or config in production.
* All `.test` domains are expected to resolve to `127.0.0.1` on your dev machine.
* Projects should not expose ports directly on the host when using this proxy; Traefik terminates TLS and routes by Host.