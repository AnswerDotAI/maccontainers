# Ubuntu container machine

This directory builds a persistent Ubuntu 24.04 environment for Apple `container`, with `systemd` running as PID 1. The normal `ubuntu:24.04` OCI image is intended to run one application and does not contain `/sbin/init`, so it cannot boot directly as a container machine. This Dockerfile installs `systemd` and masks services that do not work in this VM setup.

The recipe follows Apple's [container machine documentation](https://github.com/apple/container/blob/1.2.2/docs/container-machine.md#bring-your-own-container-machine-image).

## Build and create the machine

Start the Apple container service:

```sh
container system start
```

Then run the build and setup script:

```sh
./build.sh
```

The script registers the local `machine` DNS domain if needed, builds `local/ubuntu-machine:24.04`, creates a persistent machine named `ubuntu`, and makes it the default. Creating the DNS domain requires `sudo` the first time. It uses your current macOS short username for the Linux account, replacing any character other than a letter, digit, or underscore with `_`. The Linux account gets an independent home at `/home/<username>`.

The image sets the guest `eth0` MTU to 1400. An MTU of 1500 caused large HTTPS downloads to stall on this setup, while 1400 allows direct downloads without a host proxy. It also expands `/dev/shm` from Apple's 64 MB default to half the machine's memory so Bazel's parallel sandboxes do not exhaust it.

The setup service also remounts the guest's `/proc/sys` read-write before Docker starts. Apple initially mounts it read-only; Docker needs to configure kernel network settings, including IP forwarding, for its standard bridge network. This changes Linux guest settings, not macOS settings.

## Start the container service at login

Install a per-user LaunchAgent so `container system start` runs automatically when you log in:

```sh
./install-autostart.sh
```

The script loads the LaunchAgent immediately and for future logins. It starts Apple's container service, but leaves the Ubuntu machine stopped until `container machine run` is called.

## Use Ubuntu

Container-machine IP addresses can change. Configure SSH to use the stable name supplied by container DNS:

```sshconfig
Host ubuntu
    HostName ubuntu.machine
    User <your macOS short username>
    ForwardAgent yes
```

Normal SSH host-key checking should remain enabled. If the machine is deleted and recreated, remove its old `ubuntu.machine` host key before connecting to the replacement.

Open an interactive shell:

```sh
container machine run -n ubuntu
```

Apple still mounts your macOS home at its normal absolute path, such as `/Users/jhoward`. The setup also creates `/mnt/mac-home` as a clearer symlink to that mount. Changes under either path affect the same files on the Mac; the Linux home and its startup files remain separate.

Apple preserves the host working directory when it is under the mounted Mac home. For example, starting the machine from this directory may open the shell in `/Users/jhoward/git/maccontainers`, even though `$HOME` is `/home/jhoward`. A stopped machine starts automatically when `container machine run` is called.

## Check systemd

Run the checks in `check.sh`:

```sh
./check.sh
```

They report whether systemd reached a usable state, show the configured network MTU and shared-memory capacity, and list running services.

## UTM alternative: conventional Ubuntu Server VM

LLM setup notes. Prefer this for a normal Linux kernel, systemd, networking, and guest-local filesystem rather than Apple container compatibility workarounds. **Simplicity first:** no GUI installer automation, SSH wrapper, DHCP reservation, or Mac directory mounts. Do not apply this repository's container-specific Dockerfile, MTU, or mount fixes to the VM.

Validated 2026-09-13 with the existing Homebrew-installed **UTM 5.0.5 (build 124)** on macOS 26.6.2 / Apple Silicon. Use **Apple Virtualization**, not QEMU. VM `ubuntu`: Ubuntu Server **26.04.1 LTS**, ARM64, UEFI, 8 vCPUs, 16 GiB RAM, 100 GiB sparse raw VirtIO disk, one shared/NAT NIC with fixed MAC `02:f5:a4:b0:38:9f`, ballooning, entropy, and PTY serial; no display/audio/clipboard sharing. These resources suit the reference 18-core/128-GiB Mac; on smaller hosts keep RAM at or below half the host total. Never reuse the MAC for a second simultaneous VM.

### Unattended installation

1. Inspect before changing anything: `utmctl --help`, `utmctl version`, `utmctl list`, subcommand help, and `/Applications/UTM.app/Contents/Resources/UTM.sdef`. Do not reinstall existing UTM or overwrite an existing VM. UTM 5 has no CLI create command; use AppleScript. Keep temporary setup files/logs under this repository's `meta/ubuntu/` (never commit them), not a new directory in the home-directory root.

2. Use the [official Ubuntu ARM64 server cloud image](https://cloud-images.ubuntu.com/releases/resolute/release-20260823/) plus NoCloud cloud-init, not an interactive installer. The `.img` is **QCOW2**, which Apple Virtualization cannot use directly. With `qemu-img` available, run in the setup directory:

   ```sh
   ubuntu_images=https://cloud-images.ubuntu.com/releases/resolute/release-20260823
   curl -fLO "$ubuntu_images/SHA256SUMS"
   curl -fLO "$ubuntu_images/ubuntu-26.04-server-cloudimg-arm64.img"
   grep ' ubuntu-26.04-server-cloudimg-arm64.img$\|\*ubuntu-26.04-server-cloudimg-arm64.img$' SHA256SUMS | shasum -a 256 -c -
   # Continue only if verification succeeds.
   qemu-img convert -f qcow2 -O raw ubuntu-26.04-server-cloudimg-arm64.img ubuntu.raw
   qemu-img resize -f raw ubuntu.raw 100G
   ```

   This uses QEMU tooling only for conversion, not the VM backend. Sparse raw is deliberate: ASIF exists in UTM 5 but is not exposed by the installed scripting API.

3. Create `seed/meta-data` with a unique `instance-id` and `local-hostname: ubuntu`. Create `seed/network-config` as cloud-init network v2, matching the NIC MAC and enabling `dhcp4: true` for initial provisioning. Create `seed/user-data` (`#cloud-config`) with:
   - Hostname `ubuntu`, `manage_etc_hosts: true`, host timezone (`Australia/Brisbane` here).
   - User from `id -un` (`jhoward` here), groups `adm,sudo`, shell `/bin/bash`, `sudo: ALL=(ALL) NOPASSWD:ALL`, `lock_passwd: true`, and the existing Mac public key in `ssh_authorized_keys` (`~/.ssh/id_rsa.pub` here). Never copy private keys.
   - `ssh_pwauth: false`, `disable_root: true`; write `/etc/ssh/sshd_config.d/00-local.conf` with `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, and `PermitRootLogin no`. Reload `ssh` in `runcmd`.
   - `package_update: true`, `package_upgrade: true`; packages `openssh-server`, `ubuntu-standard`, `git`, `curl`, `wget`, `build-essential`, `ca-certificates`. The image already includes `ubuntu-server`. No Docker, desktop, or language environments.

   Build the read-only seed ISO using macOS tooling:

   ```sh
   hdiutil makehybrid -o seed.iso seed -iso -joliet -default-volume-name cidata
   ```

4. Create via `osascript` from the setup directory:

   ```sh
   osascript <<EOF
   tell application "UTM"
       set diskImage to POSIX file "$PWD/ubuntu.raw"
       set seedImage to POSIX file "$PWD/seed.iso"
       make new virtual machine with properties {backend:apple, configuration:{name:"ubuntu", cpu cores:8, memory:16384, directory shares:{}, displays:{}, network interfaces:{{mode:shared, address:"02:f5:a4:b0:38:9f"}}, drives:{{source:diskImage}, {removable:true, source:seedImage}}}}
   end tell
   EOF
   ```

   Apple creation defaults supply UEFI, ballooning, entropy, and a PTY. **Omit explicit `serial ports`:** this installed dictionary misresolved it as the `serial port` class and rejected the record. Confirm the resulting `config.plist`; the default bundle is `~/Library/Containers/com.utmapp.UTM/Data/Documents/ubuntu.utm`. The raw disk is imported into `Data/`. Make the seed self-contained too: while stopped, move `seed.iso` into `Data/`, insert string `Drive.1.ImageName = seed.iso` into `config.plist` (keeping `ReadOnly = true`), and run `osascript -e 'tell application "UTM" to reload configuration of virtual machine named "ubuntu"'`. This makes it an internal read-only VirtIO disk. After successful boot validation, discard the temporary setup artifacts; only the VM bundle is needed.

5. Start with `utmctl start ubuntu`; discover the initial address with `utmctl ip-address ubuntu`, SSH using the existing key, and wait for `sudo cloud-init status --wait`. This build discovers Apple-backend IPv4 via the first NIC's MAC and the host ARP cache—no guest agent required. The image initially reports 26.04; the apt upgrade produced **26.04.1**, kernel `7.0.0-31-generic`. No GUI interaction is needed; avoid `--hide`, which emitted OSStatus -10004 here despite successful startup.

### Static IP and normal SSH

Inspect the actual NAT subnet/gateway first (`ip route` in Ubuntu, `/etc/bootpd.plist` on the Mac); the reference setup uses `192.168.65.0/24`, gateway/DNS `192.168.65.1`. Check `.251` is not already in use. Deliberately use **192.168.65.251**, accepting the small collision risk: it remains inside Apple's `.2`–`.254` DHCP pool. **Do not change the Mac DHCP server or add a reservation/helper.**

In Ubuntu, save the original Netplan file under `~/meta/`. Write `network: {config: disabled}` to `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` so cloud-init cannot restore DHCP. Replace `/etc/netplan/50-cloud-init.yaml` (mode 0600) with:

```yaml
network:
  version: 2
  ethernets:
    enp0s1:
      dhcp4: false
      addresses: [192.168.65.251/24]
      routes:
        - to: default
          via: 192.168.65.1
      nameservers:
        addresses: [192.168.65.1]
```

Confirm the interface name, run `sudo netplan generate`, then cleanly stop/start the VM. Add this normal `~/.ssh/config` entry **before broader matching Host blocks** (substitute the actual username/key). Preserve the container's existing `Host ubuntu`:

```sshconfig
Host utm-ubuntu
    HostName 192.168.65.251
    User jhoward
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    HostKeyAlias utm-ubuntu
    StrictHostKeyChecking accept-new
```

```sh
utmctl start ubuntu
ssh utm-ubuntu
utmctl stop ubuntu --request
utmctl status ubuntu
utmctl ip-address ubuntu
utmctl attach ubuntu           # serial console
```

**Bare `utmctl stop` forces shutdown.** `--request` is asynchronous; wait for status `stopped` before starting again. No SSH polling wrapper is needed. Guest→Mac uses `192.168.65.1`; Mac services must listen beyond loopback. Shared/NAT networking does not expose the guest directly to the LAN.

### Optional Rosetta and validation

Rosetta is low priority; skip rather than build complicated workarounds. On the reference Mac it was already installed. With the VM stopped and UTM closed, insert boolean `Virtualization.Rosetta = true` into the bundle's `config.plist` (`plutil -insert Virtualization.Rosetta -bool true ...`). This is a normal UTM configuration key but is absent from the scripting interface. Do not interrupt unrelated running VMs to do this.

Inside Ubuntu, follow [UTM's Rosetta guidance](https://docs.getutm.app/advanced/rosetta/): install `binfmt-support`, create `/media/rosetta`, and add this fstab entry:

```text
rosetta /media/rosetta virtiofs ro,nofail,x-systemd.before=binfmt-support.service 0 0
```

Run `sudo systemctl daemon-reload`, `sudo mount /media/rosetta`, then register the handler; Ubuntu's existing binfmt-support service persists it without a custom service:

```sh
sudo update-binfmts --install rosetta /media/rosetta/rosetta \
  --magic '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00' \
  --mask '\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff' \
  --credentials yes --preserve yes --fix-binary yes
```

Test a real static x86_64 ELF: download [Ubuntu's amd64 BusyBox package](https://archive.ubuntu.com/ubuntu/pool/main/b/busybox/busybox-static_1.38.0-3ubuntu2_amd64.deb), extract with `dpkg-deb -x` under guest `~/meta/rosetta-test` (do not install it over native BusyBox), verify `file .../usr/bin/busybox` says x86-64, and run `.../usr/bin/busybox uname -m`; expect `x86_64`. Repeat after restart. No multiarch was needed; dynamically linked amd64 programs may need matching libraries. Rosetta translates userspace, not an x86 kernel.

Before declaring success, verify from Mac SSH: `uname -m` = `aarch64`, `/` = ext4 on `/dev/vda1` rather than VirtioFS, `/sys/firmware/efi` exists, systemd is PID 1, no failed units, hostname/timezone, passwordless sudo, requested packages and completed cloud-init, DNS/outbound HTTPS and ping to the Mac gateway. Check effective `sshd -T` settings and reject password-only authentication. Confirm the balloon driver is bound. Cleanly stop/start; recheck SSH/static address, persistent files, UTM IP lookup, and Rosetta. The initial DHCP setup measured **6.26 s** from `utmctl start` to successful SSH; static networking was separately verified across restart. Apple-backend guest-agent file/exec operations and QEMU snapshot commands are unavailable.
