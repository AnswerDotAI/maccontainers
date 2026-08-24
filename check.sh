#!/bin/sh
set -eu

container machine run -n ubuntu -- systemctl is-system-running
container machine run -n ubuntu -- ip -brief link show eth0
container machine run -n ubuntu -- df -h /dev/shm
container machine run -n ubuntu -- systemctl list-units --type=service --state=running
