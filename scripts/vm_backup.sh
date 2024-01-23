#!/bin/bash
# Copy the VMs disk to a backup volume
SOURCE="/var/lib/libvirt/images"

## All the hosts
ARR_HOSTS=("pve1.isociel.com" "pve2.isociel.com")

for HOST in "${ARR_HOSTS[@]}"
do
  printf "Hosts [%s]\n" "${HOST}"
  # rsync --rsync-path="sudo rsync -r " daniel@pve1.isociel.com:${SOURCE} /Volumes/Crucial-2T/Kubernetes/${HOST}
done
