# Backup
```sh
VM=ubuntu-1
DST_DIR=$HOME/kvm_backup

# shutdown the VM and wait
virsh shutdown ${VM}
STATUS=$(virsh domstate ${VM})
while ([ "${STATUS}" != "shut off" ] )
do
  STATUS=$(virsh domstate ${VM})
  printf "   Status of VM [%s] is: %s\n" "${VM}" "${STATUS}"
  sleep 2
done

# copy the disk
VM_FILE=$(virsh domblklist ${VM} | tail -2 | awk '{print $2}')
# sudo install -o daniel -g daniel -m 600 ${VM_FILE} ${DST_DIR}/.
sudo rsync --mkpath ${VM_FILE} ${DST_DIR}/.

# dump the manifest file
virsh dumpxml ${VM} > ${DST_DIR}/${VM}.xml
```

# Restore

```sh
virsh undefine ${VM}
VM_FILE=$(virsh domblklist ${VM} | tail -2 | awk '{print $2}')
sudo rm ${VM_FILE}
sudo rsync --mkpath ${DST_DIR}/. ${VM_FILE}
virsh define --file ${DST_DIR}/${VM}.xml
```
