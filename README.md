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
