#!/bin/sh

RUNNING_VM=($(virsh list --state-running --name))
NUM_RUNNING_VM=${#RUNNING_VM[@]}
printf "Number of running VM is %s\n\n" "${NUM_RUNNING_VM}"

for VM in "${RUNNING_VM[@]}"
do
  printf "%s is running\n" "${VM}"
done
