# local-dev-traefik-proxy

A minimal Traefik-based reverse proxy for local development.

This repo provides a shared HTTPS front-end and Docker network for multiple local projects, so each app can run at its own `*.test` domain without installing PHP, Node, Composer, or other runtime tooling directly on the host.

## Goals

- **One proxy, many apps**: run multiple Laravel, Node, or other Dockerised projects in parallel.
- **Clean separation**: this repo is infra-only; apps live in their own repos.
- **HTTPS by default**: local TLS for `*.test` domains.
- **No host pollution**: only Docker and your editor on the host OS.

## How it works

- Starts a single Traefik container on ports `80` and `443`.
- Creates a shared Docker network called `web`.
- Uses a locally generated certificate as the default TLS certificate.
- Individual projects:
  - attach their web service to the `web` network
  - opt in via Traefik labels
  - declare their own `myapp.test` (or similar) hostnames

## Requirements

- Docker
- Docker Compose plugin (`docker compose`, v2+)

Tested on Linux Mint.

This setup should also work on other platforms that support Docker, though certificate trust steps may vary by OS and browser.

No PHP, Node, Composer, or framework tooling is required on the host.

## Setup

### 1. Clone this repo

```bash
git clone <repo-url>
cd local-dev-traefik-proxy
```

### 2. Create your local domain list

Copy the example file:

```bash
cp domains.example.txt domains.txt
```

Then edit `domains.txt` and add one domain per line, for example:

```txt
myapp.test
admin.myapp.test
api.myapp.test
```

### 3. Generate the local development certificates

```bash
./scripts/update-dev-cert.sh
```

This creates:

- `certs/local-dev-traefik-ca.crt`
- `certs/local-dev-traefik-ca.key`
- `certs/dev.crt`
- `certs/dev.key`

These files are not committed.

### 4. Trust the local CA certificate

One-time step so browsers and tools accept your local HTTPS certificates.

#### Linux Mint / Debian-based Linux

```bash
sudo cp certs/local-dev-traefik-ca.crt /usr/local/share/ca-certificates/local-dev-traefik-ca.crt
sudo update-ca-certificates
```

You may also need to import the CA into Firefox separately, depending on local browser settings.

### 5. Start Traefik

```bash
docker compose up -d
```

This:

- runs Traefik on ports `80` and `443`
- creates the shared `web` network

You would generally leave this running while developing.

## Day-to-day certificate updates

If you already have the CA trusted and simply need to regenerate the leaf certificate after editing `domains.txt`, run the normal certificate generation script again:

```bash
./scripts/generate-certs.sh
```

Then restart the Traefik container from this repo.

## Using with a project

In any project you want to expose through this proxy:

### 1. Add the domain to your hosts file

For example:

```bash
127.0.0.1 myapp.test
```

### 2. Attach the project web service to the shared `web` network

In that project's `docker-compose.yml`:

```yaml
services:
  web:
    networks:
      - default
      - web
```

### 3. Add Traefik labels to the web service

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.test`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls=true"
```

### 4. Declare the shared external network in the project

```yaml
networks:
  web:
    external: true
```

### 5. Configure Laravel to trust the proxy

For Laravel 11+ style bootstrap configuration, update `bootstrap/app.php`:

```php
->withMiddleware(function (Middleware $middleware): void {
    $middleware->trustProxies(
        at: '*',
        headers: Request::HEADER_X_FORWARDED_FOR
            | Request::HEADER_X_FORWARDED_HOST
            | Request::HEADER_X_FORWARDED_PORT
            | Request::HEADER_X_FORWARDED_PROTO,
    );
})
```

For older Laravel projects, update `app/Http/Middleware/TrustProxies.php`:

```php
protected $proxies = '*';

protected $headers =
    Request::HEADER_X_FORWARDED_FOR
    | Request::HEADER_X_FORWARDED_HOST
    | Request::HEADER_X_FORWARDED_PORT
    | Request::HEADER_X_FORWARDED_PROTO;
```

### 6. Bring the project up

```bash
docker compose up -d
```

Now:

- `https://myapp.test` routes to that project's container
- multiple projects can run in parallel, each on its own `*.test` domain

## Notes / Conventions

- This stack is for local development only.
- Do not use this certificate or configuration in production.
- All `*.test` domains are expected to resolve to `127.0.0.1` on the local machine.
- Projects should not expose their own HTTP ports directly on the host when using this proxy; Traefik handles TLS termination and host-based routing.