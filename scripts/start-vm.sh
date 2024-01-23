#!/bin/bash
# Starting VMs

# Only the VM with this prefix will be started
VM_PREFIX="k8s1"

# Build an array of VM names to start
VM_TO_START=($(virsh list --all --name | grep ${VM_PREFIX}))
NUM_VM_TO_START=${#VM_TO_START[@]}
printf "Number of VMs to start is %s\n\n" "${NUM_VM_TO_START}"

for VM in "${VM_TO_START[@]}"
do
  # Start the VM only if it's not running
  STATUS=$(virsh domstate ${VM})
  if [ "${STATUS}" != "running" ]
  then
    virsh start ${VM}
  fi
  
  # Wait for the VM to be started
  STATUS=$(virsh domstate ${VM})
  while ([ "${STATUS}" != "running" ] )
  do
    STATUS=$(virsh domstate ${VM})
    printf "   Status of VM [%s] is: %s\n" "${VM}" "${STATUS}"
    sleep 2
  done
  printf "[%s] is running with status of: %s\n\n" "${VM}" "${STATUS}"
done
