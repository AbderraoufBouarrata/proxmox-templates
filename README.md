# proxmox-templates

Ansible playbooks that build Ubuntu Server LTS cloud-init templates on Proxmox and clone VMs from them.

https://github.com/user-attachments/assets/08c50b4f-c8a0-438e-a959-f1d7be02f365

## Requirements

- Ansible on your machine
- Root SSH access to the Proxmox host
- An SSH public key at `~/.ssh/id_ed25519.pub` (it is injected into every VM)

## Setup

Set your Proxmox host and the VM login in `inventory.ini`:

```ini
[proxmox]
pve ansible_host=192.168.1.1 ansible_user=root

[proxmox:vars]
ci_user=ubuntu
ci_password=change-me
```

`ci_user` is the login user in every VM. `ci_password` is that user's password. Use it for the Proxmox console and Cockpit. SSH still only accepts your key. Proxmox stores it hashed, but it sits in plain text in `inventory.ini`, so keep that file private. Changing it means rebuilding the templates. Existing clones keep their old password.

## Build the templates

```sh
ansible-playbook -i inventory.ini template.yml
```

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
- **Disk with `iothread=1` and `ssd=1`**: disk work runs in its own thread, and Ubuntu treats the disk as an SSD. If your storage is a spinning hard drive, remove `ssd=1` from `template.yml`.

On the Docker templates, container logs use Docker's `local` log driver, which caps their size so they can't fill the disk. The `ci_user` user is added to the `docker` group on first boot, so `docker` works without `sudo`.

On the GUI template, Cockpit starts at boot and listens on `https://<vm-ip>:9090`. Log in with your `ci_user` and `ci_password`. The certificate is self-signed, so the browser will warn the first time. Navigator comes from 45Drives' Ubuntu 22.04 package, because they don't publish one for 26.04.

Every run rebuilds both templates: if a VMID already exists, the old template is destroyed and replaced. The image is downloaded again only when Ubuntu has published a new one, and the Docker template gets the current Docker packages. Rerun the playbook whenever you want fresh templates. The playbook refuses to destroy a VMID that is a regular VM, not a template.

Clones you made earlier are not affected, as long as they are full clones (the default in `clone.yml`). A linked clone depends on its template, and Proxmox will refuse to destroy that template.

Defaults (change them in the `vars:` block of `template.yml`):

| Var              | Default                                              |
| ---------------- | ---------------------------------------------------- |
| `templates`      | `9999` plain, `9998` Docker, `9997` Docker + Cockpit |
| `ubuntu_release` | `resolute`                                           |
| `storage`        | `local-lvm`                                          |
| `bridge`         | `vmbr0`                                              |

## Clone a VM

```sh
ansible-playbook -i inventory.ini clone.yml \
  -e vmid=101 -e name=web01 -e ip=192.168.100.50/24 -e gw=192.168.100.1 \
  -e cores=4 -e memory=4096 -e disk=32G
```

`vmid`, `name`, `ip` and `gw` are required. `cores`, `memory` (MB) and `disk` are optional and default to `2`, `2048` and `20G`. The plain template (`9999`) is used by default. Add `-e template_id=9998` for the Docker template or `-e template_id=9997` for the Docker + Cockpit template. The playbook makes a full clone, sets its static IP, grows the disk and starts the VM.

Connect with `ssh ubuntu@192.168.100.50`, using your `ci_user` in place of `ubuntu`.

You can also clone in the Proxmox UI: right-click the template, choose **Clone**, then set the IP in the new VM's **Cloud-Init** tab.
