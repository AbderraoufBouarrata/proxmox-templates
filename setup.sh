#!/usr/bin/env bash
# One-time setup from your computer: checks Ansible and your SSH key, writes inventory.ini,
# lets your key into the Proxmox host, then builds the templates.
# Usage: ./setup.sh   (safe to rerun: finished steps are skipped, the templates are rebuilt)
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "error: $*" >&2; exit 1; }
yes_no() { local a; read -r -p "$1 [y/N] " a; [[ $a == [yY]* ]]; }

# 1. Ansible
if ! command -v ansible-playbook >/dev/null; then
  command -v brew >/dev/null || die "Ansible is missing. Install it (https://docs.ansible.com) and rerun."
  yes_no "Ansible is missing. Install it with Homebrew?" || die "Ansible is required."
  brew install ansible
fi

# 2. SSH key (template.yml injects ~/.ssh/id_ed25519.pub into every VM)
key=~/.ssh/id_ed25519
if [[ ! -f $key.pub ]]; then
  echo "No SSH key at $key.pub, creating one."
  ssh-keygen -t ed25519 -f "$key"
fi

# 3. inventory.ini: ask only for what is missing
if [[ ! -f inventory.ini ]]; then
  read -r -p "Proxmox host IP: " host
  [[ -n $host ]] || die "Proxmox host IP is required."
  (umask 077; printf '[proxmox]\npve ansible_host=%s ansible_user=root\n' "$host" > inventory.ini)
fi
if ! grep -q '^ci_user=' inventory.ini; then
  read -r -p "VM login user [ubuntu]: " user
  printf '\n[proxmox:vars]\nci_user=%s\n' "${user:-ubuntu}" >> inventory.ini
fi
if ! grep -q '^ci_password=' inventory.ini; then
  read -r -s -p "VM password: " pw; echo
  read -r -s -p "Repeat VM password: " pw2; echo
  [[ -n $pw && $pw == "$pw2" ]] || die "Passwords are empty or don't match."
  printf '\n[proxmox:vars]\nci_password=%s\n' "$pw" >> inventory.ini
fi
chmod 600 inventory.ini  # holds the VM password in plain text

# 4. Key login to the Proxmox host (asks for the root password once)
host=$(sed -n 's/.*ansible_host=\([^ ]*\).*/\1/p' inventory.ini | head -n1)
huser=$(sed -n 's/.*ansible_user=\([^ ]*\).*/\1/p' inventory.ini | head -n1)
target="${huser:-root}@$host"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" true 2>/dev/null; then
  echo "Copying your SSH key to $target (enter its password once)."
  ssh-copy-id -i "$key.pub" "$target"
fi

# 5. Build the templates
ansible-playbook -i inventory.ini playbooks/template.yml
