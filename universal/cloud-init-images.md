# Cloud-Init OS Images Catalog

Verified direct download links for official cloud-init disk images (`.qcow2`, `.img`, `.raw.xz`) across Linux, BSD, and container-optimized operating systems—no installer ISOs required.

[← Home](../README.md)

## Contents

- [Debian and Ubuntu Family](#debian-and-ubuntu-family)
- [RHEL and Enterprise Linux Family](#rhel-and-enterprise-linux-family)
- [Rolling, Minimal, and Immutable Linux](#rolling-minimal-and-immutable-linux)
- [BSD Cloud-Init Images](#bsd-cloud-init-images)
- [Windows, macOS, and Android Notes](#windows-macos-and-android-notes)
- [Fast Deployment Recipes](#fast-deployment-recipes)
- [Verification and Image Customization](#verification-and-image-customization)

## Debian and Ubuntu Family

Direct links to official upstream cloud-init disk images ready for Proxmox VE, KVM/libvirt, OpenStack, and QEMU.

| OS / Release | User | amd64 (`x86_64`) | arm64 (`aarch64`) | Checksums |
| --- | --- | --- | --- | --- |
| **Debian 13 (Trixie)** `genericcloud` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS) |
| **Debian 12 (Bookworm)** `genericcloud` | `debian` | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2) | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2) | [SHA512](https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS) |
| **Debian 12 (Bookworm)** `generic` (full drivers) | `debian` | [qcow2](https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2) | [Index](https://cloud.debian.org/images/cloud/bookworm/latest/) | [SHA512](https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS) |
| **Ubuntu 26.04 LTS (Resolute)** | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-arm64.img) | [SHA256](https://cloud-images.ubuntu.com/resolute/current/SHA256SUMS) |
| **Ubuntu 24.04 LTS (Noble)** | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img) | [SHA256](https://cloud-images.ubuntu.com/noble/current/SHA256SUMS) |
| **Ubuntu 22.04 LTS (Jammy)** | `ubuntu` | [img (qcow2)](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img) | [img (qcow2)](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-arm64.img) | [SHA256](https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS) |

> **Watch out:** Debian's `genericcloud` image strips physical hardware kernel modules (USB, PCI passthrough NICs, non-virtio HBAs) to stay small. Use `generic` instead of `genericcloud` if you pass through physical PCIe/USB devices into a KVM or Proxmox VM. Ubuntu `.img` files are QCOW2 internally—verify with `qemu-img info`.

## RHEL and Enterprise Linux Family

| OS / Release | User | x86_64 | aarch64 | Checksums / Index |
| --- | --- | --- | --- | --- |
| **Rocky Linux 10** `GenericCloud` | `rocky` | [qcow2](https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2) | [qcow2](https://dl.rockylinux.org/pub/rocky/10/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2) | [Index](https://dl.rockylinux.org/pub/rocky/10/images/x86_64/) |
| **Rocky Linux 9** `GenericCloud` | `rocky` | [qcow2](https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2) | [qcow2](https://dl.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-GenericCloud-Base.latest.aarch64.qcow2) | [CHECKSUM](https://dl.rockylinux.org/pub/rocky/9/images/x86_64/CHECKSUM) |
| **AlmaLinux 10** `GenericCloud` | `almalinux` | [qcow2](https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2) | [qcow2](https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/AlmaLinux-10-GenericCloud-latest.aarch64.qcow2) | [Index](https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/) |
| **AlmaLinux 9** `GenericCloud` | `almalinux` | [qcow2](https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2) | [qcow2](https://repo.almalinux.org/almalinux/9/cloud/aarch64/images/AlmaLinux-9-GenericCloud-latest.aarch64.qcow2) | [CHECKSUM](https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/CHECKSUM) |
| **Fedora Cloud 45** | `fedora` | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-45-1.4.x86_64.qcow2) | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-45-1.4.aarch64.qcow2) | [Index](https://download.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/x86_64/images/) |
| **Fedora Cloud 44** | `fedora` | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2) | [qcow2](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-44-1.7.aarch64.qcow2) | [Index](https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/) |
| **CentOS Stream 10** | `cloud-user` | [qcow2](https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-latest.x86_64.qcow2) | [qcow2](https://cloud.centos.org/centos/10-stream/aarch64/images/CentOS-Stream-GenericCloud-10-latest.aarch64.qcow2) | [Index](https://cloud.centos.org/centos/10-stream/x86_64/images/) |
| **CentOS Stream 9** | `cloud-user` | [qcow2](https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2) | [qcow2](https://cloud.centos.org/centos/9-stream/aarch64/images/CentOS-Stream-GenericCloud-9-latest.aarch64.qcow2) | [Index](https://cloud.centos.org/centos/9-stream/x86_64/images/) |
| **Oracle Linux 10** | `cloud-user` | [qcow2](https://yum.oracle.com/templates/OracleLinux/OL10/u1/x86_64/OL10U1_x86_64-kvm-b291.qcow2) | [Templates](https://yum.oracle.com/oracle-linux-templates.html) | [Oracle](https://yum.oracle.com/oracle-linux-templates.html) |
| **Oracle Linux 9** | `cloud-user` | [qcow2](https://yum.oracle.com/templates/OracleLinux/OL9/u8/x86_64/OL9U8_x86_64-kvm-b293.qcow2) | [qcow2](https://yum.oracle.com/templates/OracleLinux/OL9/u8/aarch64/OL9U8_aarch64-kvm-cloud-b182.qcow2) | [Oracle](https://yum.oracle.com/oracle-linux-templates.html) |

> **Watch out:** RHEL 10, Rocky 10, AlmaLinux 10, and CentOS Stream 10 require **x86-64-v3** CPU instructions (Haswell / Zen 1 or newer). On Proxmox or KVM, set VM CPU type to `host` or `x86-64-v3`—leaving the default `kvm64` causes an immediate kernel panic at boot.

## Rolling, Minimal, and Immutable Linux

| OS / Variant | Provisioner | User | x86_64 | aarch64 | Portal / Hash |
| --- | --- | --- | --- | --- | --- |
| **Arch Linux** `cloudimg` | `cloud-init` | `arch` | [qcow2](https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2) | N/A | [SHA256](https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256) |
| **Alpine 3.24** (UEFI) | `cloud-init` | `alpine` | [qcow2](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-x86_64-uefi-cloudinit-r0.qcow2) | [qcow2](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-aarch64-uefi-cloudinit-r0.qcow2) | [Alpine Cloud](https://alpinelinux.org/cloud/) |
| **Alpine 3.24** (BIOS) | `cloud-init` | `alpine` | [qcow2](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-x86_64-bios-cloudinit-r0.qcow2) | N/A | [Cloud Dir](https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/) |
| **openSUSE Tumbleweed** | `cloud-init` | `opensuse` | [qcow2](https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2) | [qcow2](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-Cloud.qcow2) | [Appliances](https://download.opensuse.org/tumbleweed/appliances/) |
| **openSUSE Leap 15.6** | `cloud-init` | `opensuse` | [qcow2](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2) | [qcow2](https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.aarch64-Cloud.qcow2) | [Appliances](https://download.opensuse.org/distribution/leap/15.6/appliances/) |
| **openSUSE MicroOS** | `Ignition` | `root` | [qcow2](https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-OpenStack-Cloud.qcow2) | [qcow2](https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-ContainerHost-OpenStack-Cloud.qcow2) | [Appliances](https://download.opensuse.org/tumbleweed/appliances/) |
| **Flatcar Linux** (Stable) | `Ignition` | `core` | [img.bz2](https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2) | [uefi.bz2](https://stable.release.flatcar-linux.net/arm64-usr/current/flatcar_production_qemu_uefi_image.img.bz2) | [Flatcar](https://stable.release.flatcar-linux.net/amd64-usr/current/) |
| **Talos Linux** (K8s) | Machine API | None | [raw.xz](https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.9.5/nocloud-amd64.raw.xz) | [Factory](https://factory.talos.dev/) | [Factory](https://factory.talos.dev/) |

## BSD Cloud-Init Images

| OS / Release | FS | User | amd64 (`x86_64`) | arm64 (`aarch64`) | Directory |
| --- | --- | --- | --- | --- | --- |
| **FreeBSD 15.0-RELEASE** | ZFS | `freebsd` | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/amd64/Latest/FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz) | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-zfs.qcow2.xz) | [FreeBSD VMs](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/) |
| **FreeBSD 15.0-RELEASE** | UFS | `freebsd` | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/amd64/Latest/FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz) | [qcow2.xz](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz) | [FreeBSD VMs](https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/) |

Decompress `.xz` or `.bz2` cloud images before importing into Proxmox or KVM:

`[NON-ROOT]`
```bash
xz -d FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz
bzip2 -d flatcar_production_qemu_image.img.bz2
```

## Windows, macOS, and Android Notes

These platforms do not ship open-license Linux-style cloud-init `.qcow2` images. Use their native image automation equivalents:

| Platform | Cloud-Init Equivalent | Official Source / Tooling |
| --- | --- | --- |
| **Windows Server** | Evaluation VHD + [Cloudbase-Init](https://cloudbase.it/cloudbase-init/) + VirtIO drivers | [Microsoft Eval Center](https://www.microsoft.com/en-us/evalcenter) (select **VHD**) + [VirtIO Drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/) |
| **macOS** (Apple Silicon) | Pre-built OCI VM images via [Tart](https://tart.run/) or [UTM](https://mac.getutm.app/) | `tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest mac-vm` |
| **Android** | Generic System Images (GSI) or AVD system images | [Android GSI Releases](https://developer.android.com/topic/generic-system-image/releases) or `sdkmanager` |

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
  --scsi0 "${STORAGE}:vm-${VMID}-disk-0,discard=on,ssd=1"
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

## Verification and Image Customization

Always verify downloaded checksums and inject `qemu-guest-agent` into stock cloud images before templating so Proxmox/KVM reports guest IPs and performs clean fsfreeze backups.

`[NON-ROOT]` / `[ROOT]`
```bash
# Verify SHA512 checksum (Debian example)
BASE="https://cloud.debian.org/images/cloud/bookworm/latest"
curl -fLO "${BASE}/SHA512SUMS"
sha512sum --ignore-missing -c SHA512SUMS

# Inspect actual disk format and virtual size before import
qemu-img info noble-server-cloudimg-amd64.img

# Inject qemu-guest-agent offline (requires libguestfs-tools)
sudo virt-customize -a debian-12-genericcloud-amd64.qcow2 \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent' \
  --truncate /etc/machine-id
```

> **Watch out:** Stock cloud-init images disable root and password login over SSH by default and do **not** include `qemu-guest-agent`. Always attach a cloud-init datasource (`NoCloud` ISO / Proxmox `ide2:cloudinit`) with an SSH public key before first boot, or you will be locked out of both SSH and the serial console.
