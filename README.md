# proxmox-templates

Ansible playbooks that build Ubuntu Server LTS cloud-init templates on Proxmox and clone VMs from them.

https://github.com/user-attachments/assets/5a1eba58-86b9-45d4-a263-7277b866fa8f

## Quick start

There are three ways to build the templates. All three run the same `template.yml`, so you get the same templates.

| Option | Where you run it | What you need |
| --- | --- | --- |
| **1. One command in the Proxmox shell (recommended)** | Proxmox host | Nothing on your computer |
| 2. `./setup.sh` | Your computer | A Mac with Homebrew, or Ansible already installed |
| 3. Manual Ansible | Your computer | Ansible, an SSH key, and an `inventory.ini` you fill in |

Option 1 is recommended because nothing gets installed on your computer and there's no SSH setup between your computer and Proxmox.

### Option 1: One command in the Proxmox shell (recommended)

Open a root shell on the Proxmox host, either in the web UI (your node → **Shell**) or over SSH (`ssh root@<proxmox-ip>`), and run:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/AbderraoufBouarrata/proxmox-templates/main/proxmox.sh)"
```

It asks for three things:

- **VM user** (default `ubuntu`): the login user in every VM.
- **VM password** (typed twice, hidden): for SSH without your key, the Proxmox console and Cockpit.
- **Your SSH public key**: paste the one line from your computer's `~/.ssh/id_ed25519.pub`. SSH logs you in with this key first, and asks for the VM password if the key isn't there.

Then it installs `ansible-core` on the Proxmox host, downloads `template.yml`, and runs it there. The password is kept in a temporary file only root can read, and it's deleted when the script finishes. Run the command again any time to rebuild the templates.

### Option 2: `./setup.sh` from your computer

```sh
./setup.sh
```

It does every setup step for you, and skips any step that's already done:

1. Installs Ansible if it's missing (with Homebrew, after asking).
2. Creates `~/.ssh/id_ed25519` if you have no key.
3. Asks for the Proxmox IP, the VM user and the VM password, and saves them in `inventory.ini`. Only you can read that file (`chmod 600`).
4. Copies your key to the Proxmox host, so you type the root password once.
5. Builds the templates.

Run it again any time to rebuild the templates. It also sets up `inventory.ini`, which `clone.yml` needs (see [Clone a VM](#clone-a-vm-optional)).

### Option 3: Manual Ansible

You need:

- Ansible on your machine
- Root SSH access to the Proxmox host
- An SSH public key at `~/.ssh/id_ed25519.pub` (it is injected into every VM)

Set your Proxmox host and the VM login in `inventory.ini`:

```ini
[proxmox]
pve ansible_host=192.168.1.1 ansible_user=root

[proxmox:vars]
ci_user=ubuntu
ci_password=change-me
```

`ci_user` is the login user in every VM. `ci_password` is that user's password, for SSH without your key, the Proxmox console and Cockpit. SSH tries your key first, then asks for this password. Proxmox stores the password hashed, but it sits in plain text in `inventory.ini`, so keep that file private.

Then build:

```sh
ansible-playbook -i inventory.ini playbooks/template.yml
```

Changing the user or password means rebuilding the templates. Clones you already made keep their old login.

## Project layout

```
proxmox-templates/
├── proxmox.sh             # option 1: run on the Proxmox host
├── setup.sh               # option 2: run on your computer
├── playbooks/
│   ├── template.yml       # builds the three templates (every option runs this)
│   └── clone.yml          # optional: clones a VM from a template
├── inventory.ini.example  # copy to inventory.ini for options 2 and 3
└── inventory.ini          # your host, VM user and password (git-ignored)
```

## The templates

| VMID   | Name                | Contents                                                                                                                                                               |
| ------ | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `9999` | `ubuntu`            | Plain Ubuntu 26.04 LTS                                                                                                                                                 |
| `9998` | `ubuntu-docker`     | Ubuntu 26.04 LTS with Docker (`docker.io`) and the Compose plugin (`docker compose`)                                                                                   |
| `9997` | `ubuntu-docker-gui` | Same as `ubuntu-docker`, plus the [Cockpit](https://cockpit-project.org) web UI and the [Navigator](https://github.com/45Drives/cockpit-navigator) file manager plugin |

The playbook downloads the Ubuntu 26.04 LTS (`resolute`) cloud image and checks it against Ubuntu's SHA256SUMS. It installs `libguestfs-tools` on the host and uses `virt-customize` to install packages into a copy of the image. Building needs internet. Clones don't.

CPU and RAM are left at Proxmox defaults, because you size each clone. Networking uses DHCP.

All templates also get:

- **QEMU guest agent**, installed and enabled. Proxmox shows each VM's IP, shuts it down cleanly, and takes consistent backups.
- **CPU type `host`**, so VMs use all of your real CPU's features, including fast encryption. This prevents live migration to a Proxmox host with a different CPU, which doesn't matter on a single host.
- **Disk with `iothread=1` and `ssd=1`**: disk work runs in its own thread, and Ubuntu treats the disk as an SSD. If your storage is a spinning hard drive, remove `ssd=1` from `playbooks/template.yml`.

On the Docker templates, container logs use Docker's `local` log driver, which caps their size so they can't fill the disk. The `ci_user` user is added to the `docker` group on first boot, so `docker` works without `sudo`.

On the GUI template, Cockpit starts at boot and listens on `https://<vm-ip>:9090`. Log in with your `ci_user` and `ci_password`. The certificate is self-signed, so the browser will warn the first time. Navigator comes from 45Drives' Ubuntu 22.04 package, because they don't publish one for 26.04.

Every run rebuilds all three templates: if a VMID already exists, the old template is destroyed and replaced. The image is downloaded again only when Ubuntu has published a new one, and the Docker template gets the current Docker packages. Rerun the playbook whenever you want fresh templates. The playbook refuses to destroy a VMID that is a regular VM, not a template.

Clones you made earlier are not affected, as long as they are full clones (the default in `clone.yml`). A linked clone depends on its template, and Proxmox will refuse to destroy that template.

Defaults (change them in the `vars:` block of `playbooks/template.yml`):

| Var              | Default                                              |
| ---------------- | ---------------------------------------------------- |
| `templates`      | `9999` plain, `9998` Docker, `9997` Docker + Cockpit |
| `ubuntu_release` | `resolute`                                           |
| `storage`        | `local-lvm`                                          |
| `bridge`         | `vmbr0`                                              |

## Clone a VM (optional)

`clone.yml` is an optional shortcut: one command makes a full clone, sets its static IP, grows the disk and starts the VM. It needs `inventory.ini`, which options 2 and 3 set up. If you used option 1, or just prefer the UI, clone in Proxmox instead (see the end of this section).

```sh
ansible-playbook -i inventory.ini playbooks/clone.yml \
  -e vmid=101 -e name=web01 -e ip=192.168.100.50/24 -e gw=192.168.100.1 \
  -e cores=4 -e memory=4096 -e disk=32G
```

`vmid`, `name`, `ip` and `gw` are required. `cores`, `memory` (MB) and `disk` are optional and default to `2`, `2048` and `20G`. The plain template (`9999`) is used by default. Add `-e template_id=9998` for the Docker template or `-e template_id=9997` for the Docker + Cockpit template. The playbook makes a full clone, sets its static IP, grows the disk and starts the VM.

Connect with `ssh ubuntu@192.168.100.50`, using your `ci_user` in place of `ubuntu`.

To clone in the Proxmox UI instead: right-click the template, choose **Clone**, then set the IP in the new VM's **Cloud-Init** tab. A UI clone keeps the template's small disk, so resize it before first boot (**Hardware** → **Hard Disk** → **Disk Action** → **Resize**).
