#!/bin/sh
set -eu
cd "$(dirname "$0")"

mac_uid=$(id -u)
mac_user=$(id -un)
linux_user=$(printf '%s' "$mac_user" | LC_ALL=C tr -c 'A-Za-z0-9_' '_')

container build -t local/ubuntu-machine:24.04 .
container machine create local/ubuntu-machine:24.04 --name ubuntu
container machine set-default ubuntu

container machine run -n ubuntu --root \
    -e "HOST_UID=$mac_uid" \
    -e "LINUX_USER=$linux_user" \
    -e "MAC_HOME=$HOME" \
    -- sh -ceu '
current_user=$(id -nu "$HOST_UID")
current_group=$(id -gn "$current_user")

if [ "$current_user" != "$LINUX_USER" ]; then
    usermod -l "$LINUX_USER" "$current_user"
    if [ -f "/etc/sudoers.d/$current_user" ]; then
        mv "/etc/sudoers.d/$current_user" "/etc/sudoers.d/$LINUX_USER"
        sed -i "s/^$current_user /$LINUX_USER /" "/etc/sudoers.d/$LINUX_USER"
    fi
fi

linux_home="/home/$LINUX_USER"
install -d -m 0755 -o "$LINUX_USER" -g "$current_group" "$linux_home"
cp -a /etc/skel/. "$linux_home/"
chown -R "$LINUX_USER:$current_group" "$linux_home"
usermod -d "$linux_home" "$LINUX_USER"
ln -sfn "$MAC_HOME" /mnt/mac-home
'
