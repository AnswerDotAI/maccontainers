#!/bin/sh
set -eu
cd "$(dirname "$0")"

container build -t local/ubuntu-machine:24.04 .
container machine create local/ubuntu-machine:24.04 --name ubuntu
container machine set-default ubuntu
