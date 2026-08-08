#!/bin/sh
set -eu

container machine run -n ubuntu -- systemctl is-system-running
container machine run -n ubuntu -- systemctl list-units --type=service --state=running
