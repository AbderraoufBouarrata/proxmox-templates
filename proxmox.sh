#!/usr/bin/env bash
# Builds the templates directly on a Proxmox host: nothing needed on your computer.
# Run as root in the Proxmox shell:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/AbderraoufBouarrata/proxmox-templates/main/proxmox.sh)"
# It installs ansible-core on the host and runs the same template.yml as setup.sh, against localhost.
set -euo pipefail
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/AbderraoufBouarrata/proxmox-templates/main}"

die() { echo "error: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."
command -v qm >/dev/null || die "qm not found: run this on a Proxmox host."

# Prompts read from the terminal, so they also work when the script is piped from curl.
read -r -p "VM login user [ubuntu]: " user </dev/tty
read -r -s -p "VM password: " pw </dev/tty; echo
read -r -s -p "Repeat VM password: " pw2 </dev/tty; echo
[[ -n $pw && $pw == "$pw2" ]] || die "Passwords are empty or don't match."
echo "Paste the SSH public key allowed into every VM (the one line from your id_ed25519.pub):"
read -r key </dev/tty
[[ $key =~ ^(ssh-|ecdsa-|sk-) ]] || die "That doesn't look like an SSH public key."

command -v ansible-playbook >/dev/null || { apt-get update -qq && apt-get install -y -qq ansible-core; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
umask 077
curl -fsSL "$REPO_RAW/playbooks/template.yml" -o "$dir/template.yml"
printf '[proxmox]\nlocalhost ansible_connection=local\n\n[proxmox:vars]\nci_user=%s\nci_password=%s\n' \
  "${user:-ubuntu}" "$pw" > "$dir/inventory.ini"
# Extra vars beat template.yml's own ssh_pubkey (a file on the machine running Ansible).
python3 -c 'import json, sys; print(json.dumps({"ssh_pubkey": sys.argv[1]}))' "$key" > "$dir/key.json"

ansible-playbook -i "$dir/inventory.ini" "$dir/template.yml" -e "@$dir/key.json"
