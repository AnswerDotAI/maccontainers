FROM ubuntu:24.04

ENV container container

RUN apt-get update && \
    apt-get install -y \
    build-essential clang cmake curl dbus git iproute2 iputils-ping man net-tools \
    ninja-build openssh-server pkg-config sudo systemd uuid-dev vim-tiny wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    yes | unminimize

RUN >/etc/machine-id
RUN >/var/lib/dbus/machine-id

RUN systemctl set-default multi-user.target
RUN systemctl mask \
      dev-hugepages.mount \
      sys-fs-fuse-connections.mount \
      systemd-update-utmp.service \
      systemd-tmpfiles-setup.service \
      console-getty.service
RUN systemctl disable \
      networkd-dispatcher.service

COPY container-machine-setup.service /etc/systemd/system/
RUN systemctl enable container-machine-setup.service

RUN sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config
