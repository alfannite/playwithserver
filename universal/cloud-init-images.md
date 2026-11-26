# Cloud-Init OS Images Catalog & Install Guide

Verified direct download links for official cloud-init disk images (`.qcow2`, `.img`, `.raw.xz`) across Linux, BSD, and virtual router appliances—plus concise visual tips for deploying them cleanly on Proxmox VE and KVM.

[← Home](../README.md)

## Contents

- [Debian and Ubuntu Family](#debian-and-ubuntu-family)
- [RHEL and Enterprise Linux Family](#rhel-and-enterprise-linux-family)
- [Rolling, Minimal, Security, and Immutable Linux](#rolling-minimal-security-and-immutable-linux)
- [BSD and Virtual Router Appliances](#bsd-and-virtual-router-appliances)
- [Windows, macOS, and Android Equivalents](#windows-macos-and-android-equivalents)
- [Cloud-Init Installation Tips and Tricks](#cloud-init-installation-tips-and-tricks)
- [Fast Deployment Recipes](#fast-deployment-recipes)
- [Verification and Debug Cheatsheet](#verification-and-debug-cheatsheet)

## Debian and Ubuntu Family

Direct upstream cloud-init images (no installer ISO needed). Choose `genericcloud` / `minimal` for VMs, `generic` if passing through physical PCIe/USB hardware, and `nocloud` only for passwordless local lab testing.

| OS / Release | User | amd64 (`x86_64`) | arm64 (`aarch64`) | Checksums |
| --- | --- | --- | --- | --- |
| **Debian 13 (Trixie)** `genericcloud` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS) |
| **Debian 13 (Trixie)** `generic` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS) |
| **Debian 12 (Bookworm)** `genericcloud` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS) |
| **Debian 12 (Bookworm)** `generic` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS) |
| **Debian 12 (Bookworm)** `nocloud` | `root` | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2) | [Index](https://cloud.debian.org/images/cloud/bookworm/latest/) | [SHA512](https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS) |
| **Debian 11 (Bullseye)** `genericcloud` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/bullseye/latest/SHA512SUMS) |
| **Ubuntu 26.04 LTS** Server | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-arm64.img) | [SHA256](https://cloud-images.ubuntu.com/resolute/current/SHA256SUMS) |
| **Ubuntu 26.04 LTS** Minimal | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/minimal/releases/resolute/release/ubuntu-26.04-minimal-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/minimal/releases/resolute/release/ubuntu-26.04-minimal-cloudimg-arm64.img) | [Index](https://cloud-images.ubuntu.com/minimal/releases/resolute/release/) |
| **Ubuntu 24.04 LTS** Server | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img) | [SHA256](https://cloud-images.ubuntu.com/noble/current/SHA256SUMS) |
| **Ubuntu 24.04 LTS** Minimal | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-arm64.img) | [Index](https://cloud-images.ubuntu.com/minimal/releases/noble/release/) |
| **Ubuntu 22.04 LTS** Server | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-arm64.img) | [SHA256](https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS) |
| **Ubuntu 22.04 LTS** Minimal | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img) | [Index](https://cloud-images.ubuntu.com/minimal/releases/jammy/release/) | [Index](https://cloud-images.ubuntu.com/minimal/releases/jammy/release/) |

> **Watch out:** Ubuntu `.img` files are QCOW2 internally (verify with `qemu-img info`). Ubuntu Minimal images omit `vim`, `man`, and interactive docs for faster boot and smaller footprints—ideal for automated K8s/Docker nodes.

## RHEL and Enterprise Linux Family

| OS / Release | User | x86_64 | aarch64 | Checksums / Index |
| --- | --- | --- | --- | --- |
| **Rocky Linux 10** `GenericCloud` | `rocky` | [qcow2](https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2) | [qcow2](https://dl.rockylinux.org/pub/rocky/10/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2) | [Index](https://dl.rockylinux.org/pub/rocky/10/images/x86_64/) |
| **Rocky Linux 9** `GenericCloud` | `rocky` | [qcow2](https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2) | [qcow2](https://dl.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-GenericCloud-Base.latest.aarch64.qcow2) | [CHECKSUM](https://dl.rockylinux.org/pub/rocky/9/images/x86_64/CHECKSUM) |
| **Rocky Linux 8** `GenericCloud` | `rocky` | [qcow2](https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2) | [qcow2](https://dl.rockylinux.org/pub/rocky/8/images/aarch64/Rocky-8-GenericCloud-Base.latest.aarch64.qcow2) | [Index](https://dl.rockylinux.org/pub/rocky/8/images/x86_64/) |
| **AlmaLinux 10** `GenericCloud` | `almalinux` | [qcow2](https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2) | [qcow2](https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/AlmaLinux-10-GenericCloud-latest.aarch64.qcow2) | [Index](https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/) |
| **AlmaLinux 9** `GenericCloud` | `almalinux` | [qcow2](https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2) | [qcow2](https://repo.almalinux.org/almalinux/9/cloud/aarch64/images/AlmaLinux-9-GenericCloud-latest.aarch64.qcow2) | [CHECKSUM](https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/CHECKSUM) |
| **AlmaLinux 8** `GenericCloud` | `almalinux` | [qcow2](https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2) | [qcow2](https://repo.almalinux.org/almalinux/8/cloud/aarch64/images/AlmaLinux-8-GenericCloud-latest.aarch64.qcow2) | [Index](https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/) |
| **Fedora Cloud 45** | `fedora` | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-45-1.4.x86_64.qcow2) | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-45-1.4.aarch64.qcow2) | [Index](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/x86_64/images/) |
| **Fedora Cloud 44** | `fedora` | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2) | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-44-1.7.aarch64.qcow2) | [Index](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/) |
| **CentOS Stream 10** | `cloud-user` | [qcow2](https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2) | [qcow2](https://cloud.centos.org/centos/10-stream/aarch64/images/CentOS-Stream-GenericCloud-10-latest.aarch64.qcow2) | [Index](https://cloud.centos.org/centos/10-stream/x86_64/images/) |
| **CentOS Stream 9** | `cloud-user` | [qcow2](https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2) | [qcow2](https://cloud.centos.org/centos/9-stream/aarch64/images/CentOS-Stream-GenericCloud-9-latest.aarch64.qcow2) | [Index](https://cloud.centos.org/centos/9-stream/x86_64/images/) |
| **Oracle Linux 10** | `cloud-user` | [qcow2](https://yum.oracle.com/templates/OracleLinux/OL10/u1/x86_64/OL10U1_x86_64-kvm-b291.qcow2) | [Templates](https://yum.oracle.com/oracle-linux-templates.html) | [Oracle](https://yum.oracle.com/oracle-linux-templates.html) |
| **Oracle Linux 9** | `cloud-user` | [qcow2](https://yum.oracle.com/templates/OracleLinux/OL9/u8/x86_64/OL9U8_x86_64-kvm-b293.qcow2) | [qcow2](https://yum.oracle.com/templates/OracleLinux/OL9/u8/aarch64/OL9U8_aarch64-kvm-cloud-b182.qcow2) | [Oracle](https://yum.oracle.com/oracle-linux-templates.html) |
| **Amazon Linux 2023** (KVM) | `ec2-user` | [qcow2](https://cdn.amazonlinux.com/al2023/os-images/latest/kvm/al2023-kvm-2023.12.20261120.0-kernel-6.1-x86_64.xfs.gpt.qcow2) | [qcow2](https://cdn.amazonlinux.com/al2023/os-images/latest/kvm-arm64/al2023-kvm-2023.12.20261120.0-kernel-6.1-arm64.xfs.gpt.qcow2) | [AL2023 Dir](https://cdn.amazonlinux.com/al2023/os-images/latest/kvm/) |

## Rolling, Minimal, Security, and Immutable Linux

| OS / Variant | Provisioner | User | x86_64 | aarch64 | Portal / Hash |
| --- | --- | --- | --- | --- | --- |
| **Arch Linux** `cloudimg` | `cloud-init` | `arch` | [qcow2](https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2) | N/A | [SHA256](https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256) |
| **Alpine 3.24** (UEFI) | `cloud-init` | `alpine` | [qcow2](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-x86_64-uefi-cloudinit-r0.qcow2) | [qcow2](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-aarch64-uefi-cloudinit-r0.qcow2) | [Alpine Cloud](https://alpinelinux.org/cloud/) |
| **Alpine 3.24** (BIOS) | `cloud-init` | `alpine` | [qcow2](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-x86_64-bios-cloudinit-r0.qcow2) | N/A | [Cloud Dir](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/) |
| **openSUSE Tumbleweed** | `cloud-init` | `opensuse` | [qcow2](https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2) | [qcow2](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-Cloud.qcow2) | [Appliances](https://download.opensuse.org/tumbleweed/appliances/) |
| **openSUSE Leap 15.6** | `cloud-init` | `opensuse` | [qcow2](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2) | [qcow2](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.aarch64-Cloud.qcow2) | [Appliances](https://download.opensuse.org/distribution/leap/15.6/appliances/) |
| **openSUSE MicroOS** | `Ignition` | `root` | [qcow2](https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-OpenStack-Cloud.qcow2) | [qcow2](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-ContainerHost-OpenStack-Cloud.qcow2) | [Appliances](https://download.opensuse.org/tumbleweed/appliances/) |
| **Fedora CoreOS 45** | `Ignition` | `core` | [qcow2.xz](https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/45.20261030.3.1/x86_64/fedora-coreos-45.20261030.3.1-qemu.x86_64.qcow2.xz) | [qcow2.xz](https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/45.20261030.3.1/aarch64/fedora-coreos-45.20261030.3.1-qemu.aarch64.qcow2.xz) | [CoreOS](https://fedoraproject.org/coreos/download/) |
| **Flatcar Linux** (Stable) | `Ignition` | `core` | [img.bz2](https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2) | [uefi.bz2](https://stable.release.flatcar-linux.net/arm64-usr/current/flatcar_production_qemu_uefi_image.img.bz2) | [Flatcar](https://stable.release.flatcar-linux.net/amd64-usr/current/) |
| **Talos Linux** (K8s) | Machine API | None | [raw.xz](https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.9.5/nocloud-amd64.raw.xz) | [Factory](https://factory.talos.dev/) | [Factory](https://factory.talos.dev/) |
| **Gentoo Linux** Cloud | `cloud-init` | `gentoo` | [qcow2](https://distfiles.gentoo.org/releases/amd64/autobuilds/current-di-amd64-cloudinit/di-amd64-cloudinit-20261122T164601Z.qcow2) | N/A | [Gentoo Dir](https://distfiles.gentoo.org/releases/amd64/autobuilds/current-di-amd64-cloudinit/) |
| **Kali Linux 2026.3** | `cloud-init` | `kali` | [tar.xz](https://kali.download/cloud-images/current/kali-linux-2026.3-cloud-genericcloud-amd64.tar.xz) | [tar.xz](https://kali.download/cloud-images/current/kali-linux-2026.3-cloud-genericcloud-arm64.tar.xz) | [Kali Cloud](https://kali.download/cloud-images/current/) |

## BSD and Virtual Router Appliances

| OS / Release | Notes | User | amd64 (`x86_64`) | arm64 (`aarch64`) | Directory |
| --- | --- | --- | --- | --- | --- |
| **FreeBSD 15.0-RELEASE** | ZFS root | `freebsd` | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/amd64/Latest/FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz) | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-zfs.qcow2.xz) | [FreeBSD VMs](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/) |
| **FreeBSD 15.0-RELEASE** | UFS root | `freebsd` | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/amd64/Latest/FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz) | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz) | [FreeBSD VMs](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/) |
| **OpenWrt 25.12.6** | EFI raw disk | `root` | [img.gz](https://downloads.openwrt.org/releases/25.12.6/targets/x86/64/openwrt-25.12.6-x86-64-generic-ext4-combined-efi.img.gz) | [Targets](https://downloads.openwrt.org/releases/25.12.6/targets/) | [OpenWrt Dir](https://downloads.openwrt.org/releases/25.12.6/targets/x86/64/) |

Decompress `.xz`, `.bz2`, `.gz`, or `.tar.xz` images before importing:

`[NON-ROOT]`
```bash
xz -d FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz
bzip2 -d flatcar_production_qemu_image.img.bz2
gzip -d openwrt-25.12.6-x86-64-generic-ext4-combined-efi.img.gz
tar -xf kali-linux-2026.3-cloud-genericcloud-amd64.tar.xz
```

## Windows, macOS, and Android Equivalents

These platforms do not ship open-license Linux-style cloud-init `.qcow2` images. Use their native image automation equivalents:

| Platform | Cloud-Init Equivalent | Official Source / Tooling |
| --- | --- | --- |
| **Windows Server** | Evaluation VHD + [Cloudbase-Init](https://cloudbase.it/cloudbase-init/) + VirtIO drivers | [Microsoft Eval Center](https://www.microsoft.com/en-us/evalcenter) (select **VHD**) + [VirtIO Drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/) |
| **macOS** (Apple Silicon) | Pre-built OCI VM images via [Tart](https://tart.run/) or [UTM](https://mac.getutm.app/) | `tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest mac-vm` |
| **Android** | Generic System Images (GSI) or AVD system images | [Android GSI Releases](https://developer.android.com/topic/generic-system-image/releases) or `sdkmanager` |

## Cloud-Init Installation Tips and Tricks

### How Cloud-Init Executes on First Boot

```mermaid
flowchart LR
    A["1. Local: Mount NoCloud ISO & Net Config"] --> B["2. Network: Bring Up NIC & Metadata"]
    B --> C["3. Config: Grow FS, Users & SSH Keys"]
    C --> D["4. Final: Packages & runcmd"]
```

### Tip 1: Always Attach Cloud-Init Drive, VirtIO SCSI, and Serial Port

Cloud images default to serial console output and expect a virtual CD-ROM datasource (`ide2: cloudinit`). Adding a **Serial Port** (`serial0`) lets you copy-paste directly inside Proxmox's `xterm.js` terminal instead of fighting noVNC.

<img src="https://raw.githubusercontent.com/proxmox/pve-docs/master/images/screenshot/gui-cloudinit-hardware.png" alt="Proxmox VE VM Hardware tab showing CloudInit Drive, VirtIO SCSI controller, and Serial Port option" width="720">

*Hardware baseline: VirtIO SCSI controller, imported disk on `scsi0`, `CloudInit Drive` attached as CD-ROM, and `Serial Port` enabled.*

### Tip 2: Inject SSH Keys, Set Static IP, and Click `Regenerate Image`

Leave **Password** blank in production and rely on an Ed25519 SSH key. If you edit IP, DNS, or SSH keys after creating the VM, **always click `Regenerate Image`** (or run `qm cloudinit update <VMID>`) before rebooting—otherwise the old ISO metadata remains mounted.

<img src="https://raw.githubusercontent.com/proxmox/pve-docs/master/images/screenshot/gui-cloudinit-config.png" alt="Proxmox VE Cloud-Init tab showing User, SSH public key, Upgrade packages, IP Config, and Regenerate Image button" width="720">

*Cloud-Init tab: set SSH public key and static IP/CIDR, then hit **Regenerate Image** whenever values change.*

### Tip 3: Put `scsi0` First in Boot Order + Enable `discard=on,iothread=1`

After `qm importdisk`, Proxmox leaves the imported disk disabled in **Options -> Boot Order** until explicitly checked. Pair `scsi0` with `discard=on` and `iothread=1` so guest `fstrim` reclaims thin-provisioned LVM/ZFS/Ceph blocks automatically.

<img src="https://raw.githubusercontent.com/proxmox/pve-docs/master/images/screenshot/gui-qemu-edit-bootorder.png" alt="Proxmox VE Edit Boot Order dialog with scsi0 enabled first and discard=on,iothread=1 configured" width="620">

*Enable `scsi0` as Boot #1 and verify `discard=on,iothread=1` on the disk string.*

### Tip 4: Change CPU Type from `x86-64-v2-AES` to `host` for EL10

Proxmox defaults new VMs to `x86-64-v2-AES`, which causes an immediate kernel panic on **Rocky 10, AlmaLinux 10, RHEL 10, and CentOS Stream 10** (`x86-64-v3` required). Set CPU **Type** to `host` (single node) or `x86-64-v3` (heterogeneous cluster live migration).

<img src="https://raw.githubusercontent.com/proxmox/pve-docs/master/images/screenshot/gui-create-vm-cpu.png" alt="Proxmox VE Create VM CPU tab highlighting CPU Type dropdown defaulting to x86-64-v2-AES" width="660">

*Change **Type** away from `Default (x86-64-v2-AES)` to `host` or `x86-64-v3` before booting EL10 cloud images.*

### Tip 5: Auto-Install `qemu-guest-agent` via `user-data` Snippet or `virt-customize`

Stock cloud images do **not** bundle `qemu-guest-agent`. Either inject it offline once into your template image (fastest boot) or attach a reusable Proxmox vendor snippet:

```yaml
# /var/lib/vz/snippets/base-agent.yaml
# Attach via: qm set 9000 --cicustom "vendor=local:snippets/base-agent.yaml"
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
  - curl
  - htop
runcmd:
  - systemctl enable --now qemu-guest-agent
```

### Tip 6: Lock Network Config After First Boot (Stop Cloud-Init Overwrites)

Once a VM is provisioned, if you edit Netplan or `/etc/network/interfaces` manually later, cloud-init may overwrite your changes on reboot unless you disable its network stage:

`[ROOT]` (inside guest VM)
```bash
echo 'network: {config: disabled}' \
  | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

> **Watch out:** Never resize a template disk smaller than the cloud image's virtual size (typically 2–10 GB). Cloud-init's `growpart` + `resizefs` modules expand the root partition automatically on first boot whenever you grow `scsi0`—no manual `fdisk` or `resize2fs` required.

## Fast Deployment Recipes

### Proxmox VE: Build a Cloud-Init Template in 60 Seconds

`[ROOT]` (run on Proxmox VE host)
```bash
VMID=9000
STORAGE="local-lvm"
BASE="https://cloud.debian.org/images/cloud/bookworm/latest"
IMG="debian-12-genericcloud-amd64.qcow2"

curl -fLO "${BASE}/${IMG}"

qm create "${VMID}" --name "debian12-cloud-tpl" \
  --memory 2048 --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 --ostype l26
qm importdisk "${VMID}" "${IMG}" "${STORAGE}"
qm set "${VMID}" --scsihw virtio-scsi-single \
  --scsi0 "${STORAGE}:vm-${VMID}-disk-0,discard=on,iothread=1,ssd=1"
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit" --boot order=scsi0
qm set "${VMID}" --serial0 socket --vga serial0 --agent enabled=1
qm set "${VMID}" --ciuser opsadmin \
  --sshkeys ~/.ssh/authorized_keys --ipconfig0 ip=dhcp
qm disk resize "${VMID}" scsi0 20G
qm template "${VMID}"
```

### KVM / libvirt: Direct Boot with `virt-install --cloud-init`

`[ROOT]` (on Linux KVM host with `virt-install` 4.0+)
```bash
IMG="/var/lib/libvirt/images/rocky9-node01.qcow2"
BASE="https://dl.rockylinux.org/pub/rocky/9/images/x86_64"
curl -fL -o "${IMG}" \
  "${BASE}/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
qemu-img resize "${IMG}" 20G

virt-install \
  --name rocky9-node01 \
  --memory 2048 --vcpus 2 --cpu host-passthrough \
  --disk path="${IMG}",format=qcow2,bus=virtio \
  --os-variant rocky9 \
  --network network=default,model=virtio \
  --graphics none --console pty,target_type=serial \
  --import \
  --cloud-init root-ssh-key="${HOME}/.ssh/id_ed25519.pub",disable=on
```

## Verification and Debug Cheatsheet

`[NON-ROOT]` / `[ROOT]`
```bash
# Verify SHA512 checksum before importing (Debian example)
BASE="https://cloud.debian.org/images/cloud/bookworm/latest"
curl -fLO "${BASE}/SHA512SUMS"
sha512sum --ignore-missing -c SHA512SUMS

# Pre-bake qemu-guest-agent offline & wipe machine-id before templating
sudo virt-customize -a debian-12-genericcloud-amd64.qcow2 \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent' \
  --truncate /etc/machine-id

# Inside guest: wait for finish, check slowest stage, validate YAML
cloud-init status --wait --long
cloud-init analyze blame
sudo cloud-init schema --system

# Force cloud-init to re-run from scratch on next boot [DESTRUCTIVE]
sudo cloud-init clean --logs --reboot
```

| Symptom | Diagnostic Command | Fix |
| --- | --- | --- |
| SSH key rejected on first boot | `sudo cat /var/log/cloud-init-output.log` | Verify datasource ISO mounted (`lsblk -f`), click `Regenerate Image`, confirm default user (`debian`/`ubuntu`/`rocky`) |
| Cloned VMs receive identical DHCP IP | `cat /etc/machine-id` | Truncate `/etc/machine-id` to 0 bytes before converting VM to template |
| Slow 2-minute hang during boot | `cloud-init analyze blame` | Static IP missing gateway or `wait-online` blocking on unplugged secondary NIC |
| Kernel panic on Rocky/Alma 10 boot | Check VM CPU model in host config | Switch VM CPU from `kvm64`/`x86-64-v2` to `host` or `x86-64-v3` |

> **Watch out:** Running `virt-customize` on a live/already-imported disk or forgetting `--truncate /etc/machine-id` causes cloned VMs to share the exact same DHCP client DUID and systemd machine-id. Always pre-bake before `qm importdisk`, then convert to template without booting the template itself.
