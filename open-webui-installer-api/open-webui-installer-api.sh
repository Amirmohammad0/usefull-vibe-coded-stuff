#!/usr/bin/env bash
# Open WebUI + OpenAI-compatible provider + bootstrap admin installer.
set -Eeuo pipefail
umask 077

INSTALL_DIR=\${OPEN_WEBUI_DIR:-/opt/open-webui-api}
DATA_DIR="$INSTALL_DIR/data"
BACKUP_DIR="$INSTALL_DIR/backups"
ENV_FILE="$INSTALL_DIR/.env"
COMPOSE_FILE="$INSTALL_DIR/compose.yaml"
CONTAINER_NAME="open-webui-api"
DEFAULT_PORT=\${OPEN_WEBUI_PORT:-3000}
DEFAULT_IMAGE=\${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}

log(){ printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
need_root(){ [[ "$EUID" -eq 0 ]] || die "Run with sudo: sudo $0 $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
compose(){ docker compose --env-file "$INSTALL_DIR/compose.env" --project-directory "$INSTALL_DIR" -f "$COMPOSE_FILE" "$@"; }

check_os(){
  [[ -r /etc/os-release ]] || die "Cannot identify operating system."
  . /etc/os-release
  [[ "\${ID:-}" == debian || "\${ID:-}" == ubuntu || " \${ID_LIKE:-} " == *debian* ]] || die "Only Debian/Ubuntu are supported."
  [[ "$(uname -m)" == x86_64 || "$(uname -m)" == aarch64 || "$(uname -m)" == arm64 ]] || warn "Architecture $(uname -m) may not be supported by the selected image."
}

install_docker(){
  if ! have docker; then
    log "Installing Docker Engine..."
    if ! have curl; then apt-get update; apt-get install -y curl ca-certificates; fi
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi
  systemctl enable --now docker
  docker compose version >/dev/null 2>&1 || {
    apt-get update
    apt-get install -y docker-compose-plugin || die "Docker Compose plugin installation failed."
  }
  docker info >/dev/null 2>&1 || die "Docker daemon is not responding."
  local version
  version="$(docker compose version --short | sed 's/^v//')"
  [[ "$(printf '%s\n' 2.30.0 "$version" | sort -V | head -n1)" == "2.30.0" ]] || die "Docker Compose 2.30.0 or newer is required. Installed: $version"
}

prompt_value(){
  local label="$1" var="$2" value
  read -r -p "$label" value
  [[ -n "$value" ]] || die "$var cannot be empty."
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "$var cannot contain line breaks."
  printf -v "$var" '%s' "$value"
}

collect_settings(){
  local api_base api_key admin_email admin_name admin_password confirm_password port
  printf '\nOpen WebUI + API provider setup\n'
  printf 'The API key and admin password are hidden while typing.\n\n'
  prompt_value "OpenAI-compatible Base URL (example: https://api.openai.com/v1): " api_base
  api_base="\${api_base%/}"
  [[ "$api_base" =~ ^https?:// ]] || die "Base URL must start with http:// or https://."
  read -r -s -p "Provider API key: " api_key; printf '\n'
  [[ -n "$api_key" && "$api_key" != *$'\n'* && "$api_key" != *$'\r'* ]] || die "API key cannot be empty or contain line breaks."
  prompt_value "Admin email: " admin_email
  [[ "$admin_email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Enter a valid email address."
  read -r -p "Admin display name [Administrator]: " admin_name
  admin_name="\${admin_name:-Administrator}"
  [[ "$admin_name" != *$'\n'* && "$admin_name" != *$'\r'* ]] || die "Admin name cannot contain line breaks."
  while :; do
    read -r -s -p "Admin password (minimum 12 characters): " admin_password; printf '\n'
    [[ "\${#admin_password}" -ge 12 ]] || { warn "Use at least 12 characters."; continue; }
    [[ "$admin_password" != *$'\n'* && "$admin_password" != *$'\r'* ]] || { warn "Password cannot contain line breaks."; continue; }
    read -r -s -p "Confirm admin password: " confirm_password; printf '\n'
    [[ "$admin_password" == "$confirm_password" ]] && break
    warn "Passwords do not match. Try again."
  done
  read -r -p "Web UI host port [$DEFAULT_PORT]: " port
  port="\${port:-$DEFAULT_PORT}"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || die "Invalid TCP port."

  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  chmod 700 "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  cat > "$ENV_FILE" <<EOF
OPEN_WEBUI_PORT=$port
OPEN_WEBUI_IMAGE=$DEFAULT_IMAGE
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
WEBUI_ADMIN_EMAIL=$admin_email
WEBUI_ADMIN_PASSWORD=$admin_password
WEBUI_ADMIN_NAME=$admin_name
ENABLE_SIGNUP=false
ENABLE_OPENAI_API=true
OPENAI_API_BASE_URL=$api_base
OPENAI_API_KEY=$api_key
EOF
  chmod 600 "$ENV_FILE"
  unset api_key admin_password confirm_password
  log "Private configuration saved to $ENV_FILE (mode 0600)."
}

write_compose(){
  local port image
  port="$(grep -m1 '^OPEN_WEBUI_PORT=' "$ENV_FILE" | cut -d= -f2-)"
  image="$(grep -m1 '^OPEN_WEBUI_IMAGE=' "$ENV_FILE" | cut -d= -f2-)"
  [[ "$port" =~ ^[0-9]+$ ]] || die "Invalid port in $ENV_FILE."
  [[ -n "$image" ]] || die "Missing image in $ENV_FILE."
  printf 'OPEN_WEBUI_PORT=%s\\nOPEN_WEBUI_IMAGE=%s\\n' "$port" "$image" > "$INSTALL_DIR/compose.env"
  chmod 600 "$INSTALL_DIR/compose.env"
  cat > "$COMPOSE_FILE" <<'EOF'
services:
  open-webui:
    image: \${OPEN_WEBUI_IMAGE}
    container_name: open-webui-api
    restart: unless-stopped
    ports:
      - "\${OPEN_WEBUI_PORT}:8080"
    env_file:
      - path: .env
        format: raw
    volumes:
      - ./data:/app/backend/data
    init: true
    security_opt:
      - no-new-privileges:true
EOF
  chmod 600 "$COMPOSE_FILE"
}

load_env(){
  [[ -f "$ENV_FILE" ]] || die "No configuration found at $ENV_FILE. Run install first."
  local value
  value="$(grep -m1 '^OPEN_WEBUI_PORT=' "$ENV_FILE" | cut -d= -f2-)"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Invalid OPEN_WEBUI_PORT in $ENV_FILE."
  OPEN_WEBUI_PORT="$value"
}

install_app(){
  need_root; check_os
  if [[ -f "$ENV_FILE" ]]; then
    warn "Existing configuration found at $INSTALL_DIR; secrets will not be overwritten."
    read -r -p "Re-deploy using existing configuration? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Cancelled."
    load_env
    write_compose
  else
    install_docker
    collect_settings
    write_compose
    load_env
  fi
  install_docker
  log "Pulling Open WebUI image..."
  compose pull
  compose up -d
  sleep 8
  status
  printf '\nOpen WebUI: http://SERVER-IP:%s\n' "$OPEN_WEBUI_PORT"
  log "Admin bootstrap runs only when the Open WebUI database has no users."
  warn "Keep .env private. It contains the provider API key and initial admin credentials."
}

status(){
  need_root
  docker ps -a --filter "name=^/\${CONTAINER_NAME}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  docker inspect "$CONTAINER_NAME" >/dev/null 2>&1 && docker inspect -f 'Container state: {{.State.Status}}' "$CONTAINER_NAME" || true
}

update_app(){ need_root; load_env; install_docker; compose pull; compose up -d; log "Updated; data preserved."; status; }
restart_app(){ need_root; load_env; compose restart; }
stop_app(){ need_root; load_env; compose stop; }
logs_app(){ need_root; load_env; compose logs --tail=200 -f; }

backup_app(){
  need_root; load_env
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  local stamp archive
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  archive="$BACKUP_DIR/open-webui-api-$stamp.tar.gz"
  compose stop
  tar -czf "$archive" -C "$INSTALL_DIR" data .env compose.env compose.yaml
  compose start
  chmod 600 "$archive"
  log "Backup created: $archive"
}

restore_app(){
  need_root
  local archive="\${2:-}"
  [[ -n "$archive" && -f "$archive" && "$archive" == *.tar.gz ]] || die "Usage: $0 restore /path/to/backup.tar.gz"
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  if [[ -n "$(find "$DATA_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    warn "Existing data will be overwritten where archive paths match."
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 0
  fi
  tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\./)' && die "Unsafe archive paths detected."
  tar -xzf "$archive" -C "$INSTALL_DIR"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  log "Restore complete. Run '$0 install' to deploy."
}

uninstall_app(){
  need_root
  if [[ -f "$COMPOSE_FILE" ]]; then load_env; compose down --remove-orphans; fi
  log "Container removed. Data, API settings, admin configuration, and backups remain at $INSTALL_DIR."
}

purge_app(){
  need_root
  warn "This permanently deletes chats, users, uploads, API key, admin settings and backups in $INSTALL_DIR."
  read -r -p "Type DELETE to confirm: " answer
  [[ "$answer" == DELETE ]] || die "Purge cancelled."
  if [[ -f "$COMPOSE_FILE" ]]; then load_env; compose down --remove-orphans || true; fi
  rm -rf -- "$INSTALL_DIR"
  log "Installation directory deleted."
}

usage(){
  cat <<EOF
Open WebUI + OpenAI-compatible API installer

Usage: sudo $0 COMMAND
  install       Interactive install (Base URL, API key, admin email/name/password)
  update        Pull configured image and redeploy
  restart       Restart container
  stop          Stop container
  status        Show container status
  logs          Follow logs
  backup        Create timestamped backup
  restore FILE  Restore backup archive
  uninstall     Remove container; preserve data and secrets
  purge         Permanently erase installation after typed confirmation
  help          Show help

Default directory: $INSTALL_DIR
Default web port: $DEFAULT_PORT
EOF
}

case "\${1:-help}" in
  install) install_app ;;
  update) update_app ;;
  restart) restart_app ;;
  stop) stop_app ;;
  status) status ;;
  logs) logs_app ;;
  backup) backup_app ;;
  restore) restore_app "$@" ;;
  uninstall) uninstall_app ;;
  purge) purge_app ;;
  help|-h|--help) usage ;;
  *) usage; die "Unknown command: $1" ;;
esac
