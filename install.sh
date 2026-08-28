#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target_user="${SUDO_USER:-${USER}}"
target_group="$(id -gn "${target_user}")"
target_home="$(getent passwd "${target_user}" | cut -d: -f6)"

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this installer as your normal desktop user, without sudo." >&2
  echo "It will request sudo only for system-owned files." >&2
  exit 1
fi

if [[ -z "${target_home}" ]]; then
  echo "Could not determine the home directory for ${target_user}." >&2
  exit 1
fi

for command in python3 smartctl lsblk systemctl udevadm install getent; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    echo "On Omarchy/Arch, install dependencies with: sudo pacman -S smartmontools util-linux" >&2
    exit 1
  fi
done

if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo "Disk Status requires Python 3.11 or newer (found $(python3 --version 2>&1))." >&2
  exit 1
fi

sudo install -Dm755 "${repo_dir}/bin/disk-health" /usr/local/bin/disk-health
sudo install -Dm755 "${repo_dir}/bin/disk-health-collect" /usr/local/bin/disk-health-collect
sudo install -Dm755 "${repo_dir}/bin/disk-health-notify" /usr/local/bin/disk-health-notify

for unit in "${repo_dir}"/systemd/system/*; do
  sudo install -Dm644 "${unit}" "/etc/systemd/system/$(basename "${unit}")"
done
sudo install -Dm644 "${repo_dir}/udev/99-disk-health.rules" /etc/udev/rules.d/99-disk-health.rules

install -d -m 0755 "${target_home}/.config/systemd/user"
for unit in "${repo_dir}"/systemd/user/*; do
  install -m644 "${unit}" "${target_home}/.config/systemd/user/$(basename "${unit}")"
done

install -d -m 0755 "${target_home}/.config/omarchy"
if [[ ! -e "${target_home}/.config/omarchy/disk-health.toml" ]]; then
  install -m644 "${repo_dir}/config/disk-health.toml.example" \
    "${target_home}/.config/omarchy/disk-health.toml"
fi

sudo install -d -m 0750 -o "${target_user}" -g "${target_group}" /var/lib/disk-health
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemctl enable --now disk-health-collect.timer disk-health-collect.path
sudo systemctl start disk-health-collect.service

if ! systemctl --user daemon-reload; then
  echo "Could not reach the systemd user session. Run the installer from your logged-in Omarchy desktop session." >&2
  exit 1
fi
systemctl --user enable --now disk-health-notify.path disk-health-notify.timer

echo
echo "Disk Status backend installed."
echo "State:  /var/lib/disk-health/disk-health.json"
echo "Config: ${target_home}/.config/omarchy/disk-health.toml"
echo "Check:  disk-health status"
