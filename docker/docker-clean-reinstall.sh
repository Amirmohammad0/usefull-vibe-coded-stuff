#!/usr/bin/env bash
#
# Docker clean removal and reinstall for Ubuntu/Debian.
# WARNING: This removes Docker images, containers, volumes, networks and
# all data stored under Docker/containerd data directories.
#
set -Eeuo pipefail

LOG_FILE="/var/log/docker-clean-reinstall.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '\n[%s] %s\n' "$(date -Is)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run this script as root: sudo $0"

[[ -r /etc/os-release ]] || die "/etc/os-release not found."
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "Supported operating systems: Ubuntu and Debian. Detected: ${ID:-unknown}" ;;
esac

CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
[[ -n "$CODENAME" ]] || die "Could not determine OS codename."
ARCH="$(dpkg --print-architecture)"
KEYRING="/etc/apt/keyrings/docker.asc"
REPO_FILE="/etc/apt/sources.list.d/docker.sources"

cat <<'WARN'

!!!!!!!!!!!!!!!!!!!!!!!! DESTRUCTIVE OPERATION !!!!!!!!!!!!!!!!!!!!!!!!
This script will completely remove Docker/containerd packages and data.

The following data may be permanently deleted:
  - All containers and their writable layers
  - All Docker images and build cache
  - All Docker volumes (including databases and application data)
  - Docker networks and local Docker configuration
  - containerd state and images

It may disrupt Kubernetes or any other workload using containerd.
Back up anything important before continuing.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
WARN

read -r -p 'Type DELETE-DOCKER-DATA to continue: ' CONFIRM
[[ "$CONFIRM" == "DELETE-DOCKER-DATA" ]] || die "Confirmation did not match. No changes made."

log "Stopping Docker/containerd services (if present)..."
for service in docker.service docker.socket containerd.service; do
  systemctl stop "$service" 2>/dev/null || true
  systemctl disable "$service" 2>/dev/null || true
done

log "Removing Docker-related packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y \
  docker-ce docker-ce-cli docker-ce-rootless-extras \
  docker-buildx-plugin docker-compose-plugin \
  docker.io docker-doc docker-compose podman-docker \
  containerd.io containerd runc || true

log "Removing Docker/containerd data and configuration..."
rm -rf \
  /var/lib/docker \
  /var/lib/containerd \
  /etc/docker \
  /run/docker \
  /run/containerd \
  /var/run/docker \
  /var/run/containerd \
  /usr/local/bin/docker-compose \
  /usr/local/lib/docker \
  /etc/default/docker \
  /etc/apparmor.d/docker

log "Removing previous Docker APT repository configuration..."
rm -f "$REPO_FILE" "$KEYRING" \
  /etc/apt/sources.list.d/docker.list \
  /etc/apt/trusted.gpg.d/docker.gpg

log "Refreshing APT and installing prerequisites..."
apt-get update
apt-get install -y ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o "$KEYRING"
chmod a+r "$KEYRING"

log "Configuring the official Docker APT repository..."
cat > "$REPO_FILE" <<EOF
Types: deb
URIs: https://download.docker.com/linux/${ID}
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: ${KEYRING}
EOF

apt-get update

log "Installing Docker Engine, CLI, containerd, Buildx and Compose plugin..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Enabling and starting Docker..."
systemctl enable docker.service
systemctl enable containerd.service
systemctl restart containerd.service
systemctl restart docker.service

log "Running Docker installation test..."
docker run --rm hello-world

log "Docker version:"
docker --version
docker compose version

log "Docker daemon status:"
systemctl --no-pager --full status docker.service || true

log "Docker installation completed successfully."
log "Full log: $LOG_FILE"
