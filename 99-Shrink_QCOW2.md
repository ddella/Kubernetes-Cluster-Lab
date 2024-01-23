# Shrink VM file
Here's an easy way to shrink a `qcow2` file. We **must** shutdown the guest VM. This doesn't reduce the virtual size of a `qcow2` disk image, it only reduces the size of the file on disk.

In this example, the `qcow2` disk image is 20Gb and the file on disk is 4.81Gb. We'll see at the end that the disk image hasn't changed but the size on disk has shrinked a lot.

## Make a backup
Make a backup copy of the `qcow2` file, just in case:
```sh
cd /var/lib/libvirt/images/ubuntu-1
sudo cp ubuntu-1.qcow2 ~/ubuntu-1.qcow2_backup
```

## Check size before
Check the file size before the shrink with the command:
```sh
sudo qemu-img info ubuntu-1.qcow2
```

Output
```
image: ubuntu-1.qcow2
file format: qcow2
virtual size: 20 GiB (21474836480 bytes)
disk size: 4.81 GiB
cluster_size: 65536
Format specific information:
    compat: 1.1
    compression type: zlib
    lazy refcounts: true
    refcount bits: 16
    corrupt: false
    extended l2: false
```

The file size is 4.81Gb before the shrink.

## Shrink
Let's shrink the file on disk:
```sh
sudo virt-sparsify ubuntu-1.qcow2 ubuntu-1.qcow2_shrinked
```

Output:
```
[   0.0] Create overlay file in /tmp to protect source disk
[   0.0] Examine source disk
[   2.2] Fill free space in /dev/sda1 with zero
 100% ⟦▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒⟧ --:--
[  24.6] Fill free space in /dev/sda15 with zero
[  25.3] Copy to destination and make sparse
[  28.7] Sparsify operation completed with no errors.
```

## Check size after
Check the file size after the shrink with the command:
```sh
sudo qemu-img info ubuntu-1.qcow2_shrinked
```

Output
```
image: ubuntu-1.qcow2_shrinked
file format: qcow2
virtual size: 20 GiB (21474836480 bytes)
disk size: 1.86 GiB
cluster_size: 65536
Format specific information:
    compat: 1.1
    compression type: zlib
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
    extended l2: false
```

Size is now 1.86Gb and the disk image hasn't changed 🎉

```sh
ls -la
```

Output
```
total 6987168
drwxr-xr-x  2 libvirt-qemu libvirt       4096 Jan 13 11:37 .
drwx--x--x 16 root         root          4096 Jan 13 10:54 ..
-rw-------  1 libvirt-qemu libvirt 5162401792 Jan 13 11:24 ubuntu-1.qcow2
-rw-r--r--  1 root         root    1992491008 Jan 13 11:37 ubuntu-1.qcow2_shrinked
```

## Let's test it
Time to spin the VM and see if it's still working:
```sh
sudo rm ubuntu-1.qcow2
sudo mv ubuntu-1.qcow2_shrinked ubuntu-1.qcow2
sudo chown libvirt-qemu:libvirt ubuntu-1.qcow2
virsh start ubuntu-1
```

## Delete Backup
Delete the backup file, if you're statisfy:
```sh
cd ~
sudo rm ubuntu-1.qcow2_backup
```
