# Open WebUI Installer (Debian / Ubuntu)

A small Bash installer and lifecycle manager for a standard, self-hosted Open WebUI deployment using Docker Compose.

## Features

- Supports Debian and Ubuntu (systemd-based hosts).
- Installs Docker Engine when it is missing, then enables the Docker service.
- Installs/checks the Docker Compose plugin.
- Uses the official `ghcr.io/open-webui/open-webui:main` image by default.
- Publishes host port `3000` to container port `8080`.
- Persists application state, accounts, chats, and uploads in `/opt/open-webui/data`.
- Generates a stable `WEBUI_SECRET_KEY` once and protects `.env` with mode `0600`.
- Uses `restart: unless-stopped` and Docker's init process.
- Includes update, restart, stop, status, logs, backup, restore, uninstall, and explicit purge commands.
- Uninstall intentionally preserves data, backups, and configuration.

## Requirements

- Debian/Ubuntu with systemd.
- Root or sudo access.
- Internet connectivity for package and container image downloads.
- Recommended: at least 2 CPU cores, 4 GB RAM, and sufficient free disk space (larger models run on a separate provider and need separate resources).

## Install

Download the script and run:

```bash
chmod +x open-webui-installer.sh
sudo ./open-webui-installer.sh install
```

Or install with a custom host port:

```bash
sudo OPEN_WEBUI_PORT=8088 ./open-webui-installer.sh install
```

After startup, open:

```
http://SERVER-IP:3000
```

Use the configured host port if it was changed. On first launch, create the administrator account. Keep the admin credentials safe.

## Commands

| Command | Purpose |
|---|---|
| `install` | Install/re-apply deployment; existing data and secret are preserved |
| `update` | Pull configured image and recreate container |
| `restart` | Restart container |
| `stop` | Stop container |
| `status` | Show container status and published port |
| `logs` | Follow recent container logs |
| `backup` | Stop briefly, archive data/configuration, then start again |
| `restore FILE.tar.gz` | Restore a previously created archive |
| `uninstall` | Remove container only; preserve installation directory |
| `purge` | Irreversibly delete the full installation directory after typed confirmation |

Examples:

```bash
sudo ./open-webui-installer.sh status
sudo ./open-webui-installer.sh logs
sudo ./open-webui-installer.sh update
sudo ./open-webui-installer.sh backup
sudo ./open-webui-installer.sh uninstall
```

## Files and persistence

```
/opt/open-webui/
├── compose.yaml
├── .env              # WEBUI_SECRET_KEY and deployment settings (0600)
├── data/             # Persistent Open WebUI database, uploads, and app state
└── backups/           # Timestamped backups (0700)
```

**Do not delete `/opt/open-webui/data` or change `WEBUI_SECRET_KEY` casually.** The data directory contains user state. The secret key should remain stable across container recreations to avoid invalidating sessions.

## Backup and restore

Create a backup:

```bash
sudo ./open-webui-installer.sh backup
```

Restore a backup:

```bash
sudo ./open-webui-installer.sh restore /opt/open-webui/backups/open-webui-YYYYMMDDTHHMMSSZ.tar.gz
```

Copy backups off the VPS and protect them as sensitive data: they may contain chat history, uploaded documents, user data, and secrets. Test restores periodically.

## Security notes

- The installer does **not** open firewall ports automatically. Allow inbound access only from trusted networks, or put the service behind a properly configured HTTPS reverse proxy.
- Port 3000 is plain HTTP. Do not expose it directly to the public Internet for production use.
- The first registered account becomes the administrator. Complete initial setup promptly.
- Keep Docker, the host OS, and Open WebUI updated.
- Protect `.env` and backup archives; they contain sensitive material.
- Docker access is effectively root-equivalent. Only trusted administrators should have access to the Docker socket/group.
- The script uses Docker's official convenience installer only when Docker is absent. Review that installer and your organization's change-control policy before running it on production systems.

## Model providers

This is a **normal standalone Open WebUI installation**. It does not configure BoxAPI, Ollama, API keys, or local inference automatically. Configure providers later from the Open WebUI admin/settings interface.

## Troubleshooting

```bash
sudo ./open-webui-installer.sh status
sudo ./open-webui-installer.sh logs
docker compose -f /opt/open-webui/compose.yaml ps
docker compose -f /opt/open-webui/compose.yaml logs --tail=200
```

If the UI does not load, verify the container is running, the host port is reachable, and your firewall/security-group allows the intended source IP.

## Upstream references

- [Open WebUI Quick Start](https://docs.openwebui.com/getting-started/quick-start/)
- [Environment Variable Configuration](https://docs.openwebui.com/reference/env-configuration/)
- [Open WebUI FAQ – Data Persistence](https://docs.openwebui.com/faq/)

## License

MIT (see repository-level license, if present).
