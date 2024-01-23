#!/bin/sh
# Shutdown all running VMs

RUNNING_VM=($(virsh list --state-running --name))
NUM_RUNNING_VM=${#RUNNING_VM[@]}
printf "Number of running VM is %s\n\n" "${NUM_RUNNING_VM}"

for VM in "${RUNNING_VM[@]}"
do
  virsh shutdown ${VM}
  STATUS=$(virsh domstate ${VM})
  while ([ "${STATUS}" != "shut off" ] )
  do
    STATUS=$(virsh domstate ${VM})
    printf "   Status of VM [%s] is: %s\n" "${VM}" "${STATUS}"
    sleep 2
  done
  printf "[%s] is shutdown with status of: %s\n\n" "${VM}" "${STATUS}"
done
