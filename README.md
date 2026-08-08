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

The script builds `local/ubuntu-machine:24.04`, creates a persistent machine named `ubuntu`, and makes it the default. It uses your current macOS short username for the Linux account, replacing any character other than a letter, digit, or underscore with `_`. The Linux account gets an independent home at `/home/<username>`.

## Use Ubuntu

Open an interactive shell:

```sh
container machine run -n ubuntu
```

Apple still mounts your macOS home at its normal absolute path, such as `/Users/jhoward`. The setup also creates `/mnt/mac-home` as a clearer symlink to that mount. Changes under either path affect the same files on the Mac; the Linux home and its startup files remain separate.

Apple preserves the host working directory when it is under the mounted Mac home. For example, starting the machine from this directory may open the shell in `/Users/jhoward/git/maccontainers`, even though `$HOME` is `/home/jhoward`. A stopped machine starts automatically when `container machine run` is called.

## Check systemd

Run the two checks in `check.sh`:

```sh
./check.sh
```

The first reports whether systemd reached a usable state. The second lists running services.
