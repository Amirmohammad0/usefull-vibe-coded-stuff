# Docker Clean Reinstall

A destructive Bash utility to remove Docker/containerd packages and local data, then reinstall Docker Engine from the official Docker APT repository.

## Supported systems

- Ubuntu
- Debian

The script uses the operating system codename and architecture detected from the host.

## ⚠️ Data-loss warning

**This script permanently deletes Docker/containerd data**, including:

- Containers and writable layers
- Images and build cache
- Volumes (including databases and application data)
- Networks and Docker configuration
- containerd state and images

It can also disrupt Kubernetes and other workloads that depend on containerd.

Back up required data and verify that no critical workload depends on Docker/containerd before running it. The script asks for the exact confirmation string `DELETE-DOCKER-DATA` before making changes.

## Usage

Review the script before execution:

```bash
curl -fsSLO https://raw.githubusercontent.com/Amirmohammad0/usefull-vibe-coded-stuff/main/docker/docker-clean-reinstall.sh
less docker-clean-reinstall.sh
chmod +x docker-clean-reinstall.sh
sudo ./docker-clean-reinstall.sh
```

When prompted, enter:

```text
DELETE-DOCKER-DATA
```

## What it does

1. Checks for root privileges and a supported OS.
2. Stops and disables Docker/containerd services.
3. Purges common Docker/containerd packages.
4. Removes Docker/containerd data and configuration directories.
5. Removes old Docker APT repository configuration.
6. Adds Docker's official signing key and APT repository.
7. Installs Docker Engine, CLI, containerd, Buildx and the Compose plugin.
8. Enables and starts the services.
9. Runs `docker run --rm hello-world` as a basic installation check.

Execution output is logged to:

```text
/var/log/docker-clean-reinstall.log
```

## Important notes

- This is intended for fresh installation/recovery scenarios, not routine Docker upgrades.
- Review the script and adapt it to your environment before running it.
- It does not run `apt autoremove`, to avoid removing unrelated packages automatically.
- Adding a user to the `docker` group grants root-equivalent privileges.

## License

No license has been specified yet. Check with the repository owner before redistributing or incorporating this script into another project.
