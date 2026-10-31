#!/usr/bin/env bash
# Open WebUI installer and manager for Debian/Ubuntu.
# Data is stored in /opt/open-webui/data and is never removed by uninstall/update.
set -Eeuo pipefail

APP_NAME="open-webui"
INSTALL_DIR="${OPEN_WEBUI_DIR:-/opt/open-webui}"
DATA_DIR="$INSTALL_DIR/data"
BACKUP_DIR="$INSTALL_DIR/backups"
ENV_FILE="$INSTALL_DIR/.env"
COMPOSE_FILE="$INSTALL_DIR/compose.yaml"
IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
DEFAULT_PORT="${OPEN_WEBUI_PORT:-3000}"
CONTAINER_NAME="open-webui"

log(){ printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
need_root(){ [[ "${EUID}" -eq 0 ]] || die "Run as root (sudo $0 $*)"; }
have(){ command -v "$1" >/dev/null 2>&1; }
compose(){ docker compose --project-directory "$INSTALL_DIR" -f "$COMPOSE_FILE" "$@"; }

check_os(){
  [[ -r /etc/os-release ]] || die "Cannot identify operating system."
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || " ${ID_LIKE:-} " == *"debian"* ]] || die "Supported systems: Debian/Ubuntu."
  [[ "$(uname -m)" == "x86_64" || "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]] || warn "Architecture $(uname -m) may not have a compatible image."
}

install_docker(){
  if ! have docker; then
    log "Installing Docker Engine using Docker's official convenience installer..."
    have curl || { apt-get update; apt-get install -y curl ca-certificates; }
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi
  systemctl enable --now docker
  if ! docker compose version >/dev/null 2>&1; then
    log "Installing Docker Compose plugin..."
    apt-get update
    apt-get install -y docker-compose-plugin || apt-get install -y docker-compose-v2 || die "Docker Compose plugin could not be installed."
  fi
  docker info >/dev/null 2>&1 || die "Docker daemon is not responding."
}

make_env(){
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
  chmod 700 "$INSTALL_DIR" "$BACKUP_DIR"
  if [[ ! -f "$ENV_FILE" ]]; then
    local secret
    secret="$(openssl rand -hex 32)"
    cat > "$ENV_FILE" <<EOF
# Open WebUI settings. Keep this file private.
OPEN_WEBUI_PORT=$DEFAULT_PORT
OPEN_WEBUI_IMAGE=$IMAGE
WEBUI_SECRET_KEY=$secret
EOF
    chmod 600 "$ENV_FILE"
    log "Created private environment file: $ENV_FILE"
  else
    chmod 600 "$ENV_FILE"
    log "Existing .env preserved."
  fi
}

write_compose(){
  cat > "$COMPOSE_FILE" <<'EOF'
services:
  open-webui:
    image: ${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}
    container_name: open-webui
    restart: unless-stopped
    ports:
      - "${OPEN_WEBUI_PORT:-3000}:8080"
    environment:
      WEBUI_SECRET_KEY: ${WEBUI_SECRET_KEY:?WEBUI_SECRET_KEY is required}
    volumes:
      - ./data:/app/backend/data
    extra_hosts:
      - "host.docker.internal:host-gateway"
    init: true
    security_opt:
      - no-new-privileges:true
EOF
  chmod 600 "$COMPOSE_FILE"
}

load_env(){
  [[ -f "$ENV_FILE" ]] || die "Not installed: $ENV_FILE not found. Run '$0 install'."
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

install_app(){
  need_root
  check_os
  install_docker
  make_env
  write_compose
  load_env
  log "Pulling image: ${OPEN_WEBUI_IMAGE:-$IMAGE}"
  compose pull
  compose up -d
  log "Installation started. Waiting briefly for startup..."
  sleep 5
  status
  printf '\nOpen WebUI URL: http://SERVER-IP:%s\n' "${OPEN_WEBUI_PORT:-$DEFAULT_PORT}"
  warn "Create the first administrator account during initial setup. Do not expose this port publicly without HTTPS/reverse proxy and firewall controls."
}

status(){
  need_root
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker inspect -f 'Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}not configured{{end}}' "$CONTAINER_NAME" 2>/dev/null || true
  fi
}

update_app(){
  need_root; load_env
  log "Pulling configured image..."
  compose pull
  compose up -d
  log "Update complete. Persistent data was not modified."
  status
}

restart_app(){ need_root; load_env; compose restart; }
stop_app(){ need_root; load_env; compose stop; }
logs_app(){ need_root; load_env; compose logs --tail=200 -f; }

backup_app(){
  need_root
  [[ -d "$DATA_DIR" ]] || die "Data directory not found: $DATA_DIR"
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  local stamp archive
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  archive="$BACKUP_DIR/open-webui-$stamp.tar.gz"
  if [[ -f "$COMPOSE_FILE" ]]; then load_env; compose stop; fi
  tar -czf "$archive" -C "$INSTALL_DIR" data .env compose.yaml
  if [[ -f "$COMPOSE_FILE" ]]; then compose start; fi
  chmod 600 "$archive"
  log "Backup created: $archive"
}

restore_app(){
  need_root
  local archive="${2:-}"
  [[ -n "$archive" && -f "$archive" ]] || die "Usage: $0 restore /path/to/backup.tar.gz"
  [[ "$archive" == *.tar.gz ]] || die "Backup must be a .tar.gz archive."
  mkdir -p "$INSTALL_DIR"
  if [[ -d "$DATA_DIR" ]] && find "$DATA_DIR" -mindepth 1 -print -quit | grep -q .; then
    warn "Current data exists. Create a backup before restoring."
    read -r -p "Continue and overwrite matching files? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 0
  fi
  tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\./)' && die "Unsafe archive paths detected."
  need_root
  mkdir -p "$DATA_DIR" "$BACKUP_DIR"
  tar -xzf "$archive" -C "$INSTALL_DIR"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  log "Restore extracted. Run '$0 install' or '$0 restart' to start the service."
}

uninstall_app(){
  need_root
  if [[ -f "$COMPOSE_FILE" ]]; then load_env; compose down --remove-orphans; fi
  # Deliberately do not delete data, backups, .env or compose files.
  log "Container stopped and removed. Data and configuration preserved at $INSTALL_DIR."
  log "To reinstall, run: $0 install"
  log "To permanently erase all app data, run: $0 purge (irreversible)."
}

purge_app(){
  need_root
  warn "This permanently deletes $INSTALL_DIR including chats, users, uploads, backups and secrets."
  read -r -p "Type DELETE to confirm: " answer
  [[ "$answer" == "DELETE" ]] || die "Purge cancelled."
  if [[ -f "$COMPOSE_FILE" ]]; then load_env; compose down --remove-orphans || true; fi
  rm -rf -- "$INSTALL_DIR"
  log "Application directory permanently removed."
}

usage(){
  cat <<EOF
Open WebUI installer / manager

Usage: sudo $0 <command> [arguments]

Commands:
  install                 Install or re-apply configuration; preserves existing data
  update                  Pull configured image and recreate container
  restart                 Restart the service
  stop                    Stop the service
  status                  Show container status and ports
  logs                    Follow recent logs
  backup                  Create a timestamped backup in $BACKUP_DIR
  restore <archive.tar.gz> Restore a backup (make a backup first)
  uninstall               Remove container only; KEEP all data/configuration
  purge                   Permanently delete the entire installation directory
  help                    Show this help

Optional environment overrides:
  OPEN_WEBUI_DIR=/opt/open-webui
  OPEN_WEBUI_PORT=3000
  OPEN_WEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
EOF
}

cmd="${1:-help}"
case "$cmd" in
  install) install_app ;;
  update) update_app ;;
  restart) need_root; load_env; compose restart ;;
  stop) stop_app ;;
  status) status ;;
  logs) logs_app ;;
  backup) backup_app ;;
  restore) restore_app "$@" ;;
  uninstall) uninstall_app ;;
  purge) purge_app ;;
  help|-h|--help) usage ;;
  *) usage; die "Unknown command: $cmd" ;;
esac
