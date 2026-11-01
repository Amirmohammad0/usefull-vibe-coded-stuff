# Open WebUI + API Installer

Interactive installer for Open WebUI with an OpenAI-compatible API provider and an automatically bootstrapped administrator account.

## Interactive setup

The installer asks for:
1. Provider Base URL (e.g. `https://api.openai.com/v1` or a compatible gateway URL)
2. Provider API key (hidden input)
3. Administrator email
4. Administrator display name
5. Administrator password (hidden + confirmation; minimum 12 characters)
6. Host port (default `3000`)

It configures `OPENAI_API_BASE_URL`, `OPENAI_API_KEY`, `WEBUI_ADMIN_EMAIL`, `WEBUI_ADMIN_PASSWORD`, `WEBUI_ADMIN_NAME`, and disables public signup.

## Install

```bash
git clone https://github.com/Amirmohammad0/usefull-vibe-coded-stuff.git
cd usefull-vibe-coded-stuff/open-webui-installer-api
chmod +x open-webui-installer-api.sh
sudo ./open-webui-installer-api.sh install
```

Open `http://SERVER-IP:3000` (or the port selected during setup) and sign in with the admin credentials entered during installation.

## Requirements

- Debian or Ubuntu with systemd; root/sudo access; internet access.
- Docker Engine and Docker Compose plugin (installed if missing).
- Docker Compose 2.30.0+ (the Compose `env_file.format: raw` option is used so credentials containing shell metacharacters are passed literally).

## Management

```bash
sudo ./open-webui-installer-api.sh status
sudo ./open-webui-installer-api.sh logs
sudo ./open-webui-installer-api.sh update
sudo ./open-webui-installer-api.sh backup
sudo ./open-webui-installer-api.sh restart
```

Commands: `install`, `update`, `restart`, `stop`, `status`, `logs`, `backup`, `restore FILE`, `uninstall`, `purge`.

## Persistent layout

```
/opt/open-webui-api/
├── compose.yaml
├── compose.env # non-secret Compose interpolation values (0600)
├── .env       # provider API key, admin bootstrap credentials, secret key (0600)
├── data/      # users, chats, uploads and database
└── backups/
```

Directories are mode 0700; .env and backup archives are mode 0600. Never commit or share them.

## Important notes

- Open WebUI creates the configured admin account only when its database is empty. These variables do not reset an existing user's password.
- Open WebUI persists several configuration variables in its database after first startup. For later API connection changes, use the Admin Panel; changing .env alone may not override a persisted ConfigVar.
- Use a least-privilege API key, not a provider master key.
- The installer does not open firewall ports or configure TLS. Use a TLS reverse proxy and restrict inbound access for public deployments.
- Default image tag is `main`; for production, pin a tested release tag.
- `uninstall` preserves all data/configuration. `purge` is destructive and requires typing `DELETE`.

## Official references

- [Environment variables](https://docs.openwebui.com/reference/env-configuration/)
- [Quick Start](https://docs.openwebui.com/getting-started/quick-start/)
- [API Keys](https://docs.openwebui.com/features/authentication-access/api-keys/)

This variant installs one OpenAI-compatible provider. It does not install Ollama or local inference.
