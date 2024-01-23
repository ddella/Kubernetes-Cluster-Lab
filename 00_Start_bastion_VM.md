# Start Linux `bastion` VMs
This tutorial will show how to create Linux Ubuntu 22.04.3 LTS VMs for my Kubernetes Cluster. The VMs will serve as the `bastion` hosts. to manage my Kubernetes Cluster.

|Role|FQDN|IP|OS|Kernel|RAM|vCPU|Node|
|----|----|----|----|----|----|----|----|
|Bastion|k8s1bastion1.kloud.lan|10.100.1.101|Ubuntu 22.04.3|6.6.1|2G|2|pve1|
|Bastion|k8s1bastion2.kloud.lan|10.100.1.201|Ubuntu 22.04.3|6.6.1|2G|2|pve2|

----------
----------
----------
----------
----------
# Node PVE1
> [!IMPORTANT]  
> This section applies to node `pve1`.

## Define Variables
Define all the variables needed for the scripts below. Make sure you execute the scripts in the same window as the one you defined the variables.
```sh
# VM template. This VM must be shutdown
ORIGINAL="ubuntu-1"

# Declare a "kindOf" dictionnary
declare -A newVM
newVM[k8s1bastion1]="10.100.1.101"

# Subnet info for the VMs
localSubnet="10.100.1.0"
subnetMask="24"
defaultGateway="10.100.1.1"
localBroadcast="10.100.1.255"

# The switch
BRIDGE="br_bastion_1"

# VxLAN variables
VXLAN_ID="10100"
VXLAN_NAME="bastion-10100"
VTEP1_ADDR="192.168.11.1"
VTEP2_ADDR="192.168.11.2"
VTEP_DEV="eth1"
```

## Creating a new virtual network
Create a Linux bridge with an IP address that will be the default gateway for all the VMs connected to it.

If you use the command line, the bridge and VXLAN won't persist a reboot. If you use `netplan`, all the configurations will be persistent.

### Command Line (Do NOT use)
Don't use the CLI to create the bridge, VxLAN and NAT rules. They won't survive the node's reboot. The commands are shown for learning purposes only.
```sh
sudo ip link add "${BRIDGE}" type bridge
sudo ip link set ${BRIDGE} up
sudo ip addr add ${defaultGateway}/${subnetMask} broadcast ${localBroadcast} dev ${BRIDGE}
```

If you have two servers, you need to connect the bridges together with a tunneling protocol like VXLAN.

> [!WARNING]  
> The line `sudo ip link add ${VXLAN_NAME} ...` should be applied to ONLY one node. Read before applying blindly 😉

```sh
# Create a VXLAN tunnel interface on pve1 (towards pve2) *** YOU DO THIS COMMAND ON ONE NODE "1" NOT BOTH ***
sudo ip link add ${VXLAN_NAME} type vxlan id ${VXLAN_ID} local ${VTEP1_ADDR} remote ${VTEP2_ADDR} dev ${VTEP_DEV} dstport 4789

# Create a VXLAN tunnel interface on pve2 (towards pve1) *** YOU DO THIS COMMAND ON ONE NODE "2" NOT BOTH ***
sudo ip link add ${VXLAN_NAME} type vxlan id ${VXLAN_ID} local ${VTEP2_ADDR} remote ${VTEP1_ADDR} dev ${VTEP_DEV} dstport 4789

# Attach the vxlan interface to the bridge:
sudo ip link set ${VXLAN_NAME} master ${BRIDGE}
sudo ip link set ${VXLAN_NAME} up

# set MTU
sudo ip link set dev ${VTEP_DEV} mtu 9000
sudo ip link set dev ${VXLAN_NAME} mtu 8950
```

### Netplan (Prefered method)
The commands above are for CLI only. They will **not** persist a reboot of the node. The prefered way to configure Linux bridges and VxLAN is with `netpaln`. Add the following files in your `/etc/netplan/` directory and use the command `sudo netplan apply` to apply the configurations. This will persist when the node reboots:

Linux Bridge configuration:
```sh
cat <<EOF | sudo tee /etc/netplan/10-${BRIDGE}-config.yaml > /dev/null
# Let NetworkManager manage all devices on this system
# 10-bridges-config.yaml
network:
  version: 2
  renderer: NetworkManager
  bridges:
    ${BRIDGE}:
      addresses: [ ${defaultGateway}/${subnetMask} ]
      mtu: 9000
EOF
sudo chmod 600 /etc/netplan/10-${BRIDGE}-config.yaml
```

Linux VxLAN between the bridges on each node:
```sh
cat <<EOF | sudo tee /etc/netplan/11-${VXLAN_NAME}-config.yaml > /dev/null
# 11-vxlans-config.yaml
# https://github.com/canonical/netplan/blob/main/examples/vxlan.yaml
# https://netplan.readthedocs.io/en/latest/netplan-yaml/#properties-for-device-type-tunnels
network:
  renderer: networkd
  tunnels:
    ${VXLAN_NAME}:
      mode: vxlan
      id: ${VXLAN_ID}
      link: ${VTEP_DEV}
      mtu: 8950
      port: 4789
      local: ${VTEP1_ADDR}
      remote: ${VTEP2_ADDR}
  bridges:
    ${BRIDGE}:
      interfaces:
        - ${VXLAN_NAME}
EOF
sudo chmod 600 /etc/netplan/11-${VXLAN_NAME}-config.yaml
```

Apply the change to create the bridge and VxLAN:
```sh
  sudo netplan apply
```

## Create the VMs
### Clone VM
Start by cloning a valid VM. Make sure the template VM is shutdown:
```sh
virsh shutdown ${ORIGINAL}
for NEW in "${!newVM[@]}"
do
  # Create the new directory
  sudo install -v -d -g libvirt -o libvirt-qemu /var/lib/libvirt/images/${NEW}

  # Clone the VM
  sudo virt-clone --connect qemu:///system \
  --original ${ORIGINAL} --name ${NEW} \
  --file /var/lib/libvirt/images/${NEW}/${NEW}.qcow2

  # Change permission
  sudo chown libvirt-qemu:libvirt /var/lib/libvirt/images/${NEW}/${NEW}.qcow2
done
```

### Customize the VMs
Once you have cloned the VM, you can customize the new virtual machines with `virt-sysprep` utility. Make sure the utility is installed with the command `sudo apt install guestfs-tools`
```sh
OPERATIONS=$(virt-sysprep --list-operations | egrep -v 'lvm-uuids|fs-uuids|ssh-hostkeys|ssh-userdir' | awk '{ printf "%s,", $1}' | sed 's/,$//')

for NEW in "${!newVM[@]}"
do
  sudo virt-sysprep -d ${NEW} \
  --hostname ${NEW}.kloud.lan \
  --enable ${OPERATIONS} \
  --keep-user-accounts daniel \
  --run-command "sed -i \"s/127.0.1.1.*/127.0.1.1 ${NEW}/\" /etc/hosts" \
  --run-command "sed -i \"s/127.0.0.1 localhost/127.0.0.1 localhost ${NEW}/\" /etc/hosts" \
  --run-command "sed -i \"s/10.103.1.10/${newVM[${NEW}]}/\" /etc/netplan/50-cloud-init.yaml" \
  --run-command "sed -i \"s/10.103.1.1/${defaultGateway}/\" /etc/netplan/50-cloud-init.yaml"
done
```

### Attach VM to bridge
> [!NOTE]  
> You can skip this section if your VM template has the correct bridge network configured.

Attach the VM to the bridge network:
```sh
cat <<EOF >net.xml
<interface type='bridge'>
  <source bridge="${BRIDGE}"/>
  <model type='virtio'/>
  <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0' multifunction='on'/>
</interface>
EOF

for NEW in "${!newVM[@]}"
do
  virsh update-device ${NEW} net.xml
done

rm -f net.xml
```

## Start the VMs
Start the VMs.

> [!NOTE]  
> By default the VMs won't auto start. I added the line `virsh autostart ${NEW}` for them to start automaticaly.

```sh
#!/bin/bash
for NEW in "${!newVM[@]}"
do
  printf "Starting VM %s\n" "${NEW}"
  virsh start ${NEW}
  virsh autostart ${NEW}
done
```

## Add SNAT
You can add a source NAT rule for the VMs to access the Internet via the node's default gateway. This command configure the NAT.

IF THE FILE `/etc/iptables/rules.v4` EXISTS use this command:
```sh
sudo sed -i -e '/# Forward traffic.*/a\' -e "-A POSTROUTING -s ${localSubnet}/${subnetMask} -o eth0 -j MASQUERADE" /etc/iptables/rules.v4
```

If the file `/etc/iptables/rules.v4` doesn't exist, use the following:
```sh
cat <<EOF | sudo tee -a /etc/iptables/rules.v4
# nat Table rules
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic from VM subnets through eth0.
-A POSTROUTING -s ${localSubnet}/${subnetMask} -o eth0 -j MASQUERADE

# don't delete the 'COMMIT' line or these nat table rules won't be processed
COMMIT
EOF
```

You can apply the rules with the command:
```sh
sudo iptables-restore /etc/iptables/rules.v4
```
----------
----------
----------
----------
----------
# Node PVE2
> [!IMPORTANT]  
> This section applies to node `pve2`.

## Define Variables
Define all the variables needed for the scripts below. Make sure you execute the scripts in the same window as the one you defined the variables.
```sh
# VM template. This VM must be shutdown
ORIGINAL="ubuntu-1"

# Declare a "kindOf" dictionnary
declare -A newVM
newVM[k8s1bastion2]="10.100.1.201"

# Subnet info for the VMs
localSubnet="10.100.1.0"
subnetMask="24"
defaultGateway="10.100.1.2"
localBroadcast="10.100.1.255"

# The switch
BRIDGE="br_bastion_1"

# VxLAN variables
VXLAN_ID="10100"
VXLAN_NAME="bastion-10100"
VTEP1_ADDR="192.168.11.2"
VTEP2_ADDR="192.168.11.1"
VTEP_DEV="eth1"
```

## Creating a new virtual network
Create a Linux bridge with an IP address that will be the default gateway for all the VMs connected to it.

If you use the command line, the bridge and VXLAN won't persist a reboot. If you use `netplan`, all the configurations will be persistent.

### Command Line (Do NOT use)
Don't use the CLI to create the bridge, VxLAN and NAT rules. They won't survive the node's reboot. The commands are shown for learning purposes only.
```sh
sudo ip link add "${BRIDGE}" type bridge
sudo ip link set ${BRIDGE} up
sudo ip addr add ${defaultGateway}/${subnetMask} broadcast ${localBroadcast} dev ${BRIDGE}
```

If you have two servers, you need to connect the bridges together with a tunneling protocol like VXLAN.

> [!WARNING]  
> The line `sudo ip link add ${VXLAN_NAME} ...` should be applied to ONLY one node. Read before applying blindly 😉

```sh
# Create a VXLAN tunnel interface on pve1 (towards pve2) *** YOU DO THIS COMMAND ON ONE NODE "1" NOT BOTH ***
sudo ip link add ${VXLAN_NAME} type vxlan id ${VXLAN_ID} local ${VTEP1_ADDR} remote ${VTEP2_ADDR} dev ${VTEP_DEV} dstport 4789

# Create a VXLAN tunnel interface on pve2 (towards pve1) *** YOU DO THIS COMMAND ON ONE NODE "2" NOT BOTH ***
sudo ip link add ${VXLAN_NAME} type vxlan id ${VXLAN_ID} local ${VTEP2_ADDR} remote ${VTEP1_ADDR} dev ${VTEP_DEV} dstport 4789

# Attach the vxlan interface to the bridge:
sudo ip link set ${VXLAN_NAME} master ${BRIDGE}
sudo ip link set ${VXLAN_NAME} up

# set MTU
sudo ip link set dev ${VTEP_DEV} mtu 9000
sudo ip link set dev ${VXLAN_NAME} mtu 8950
```

### Netplan (Prefered method)
The commands above are for CLI only. They will **not** persist a reboot of the node. The prefered way to configure Linux bridges and VxLAN is with `netpaln`. Add the following files in your `/etc/netplan/` directory and use the command `sudo netplan apply` to apply the configurations. This will persist when the node reboots:

Linux Bridge configuration:
```sh
cat <<EOF | sudo tee /etc/netplan/10-${BRIDGE}-config.yaml > /dev/null
# Let NetworkManager manage all devices on this system
# 10-bridges-config.yaml
network:
  version: 2
  renderer: NetworkManager
  bridges:
    ${BRIDGE}:
      addresses: [ ${defaultGateway}/${subnetMask} ]
      mtu: 9000
EOF
sudo chmod 600 /etc/netplan/10-${BRIDGE}-config.yaml
```

Linux VxLAN between the bridges on each node:
```sh
cat <<EOF | sudo tee /etc/netplan/11-${VXLAN_NAME}-config.yaml > /dev/null
# 11-vxlans-config.yaml
# https://github.com/canonical/netplan/blob/main/examples/vxlan.yaml
# https://netplan.readthedocs.io/en/latest/netplan-yaml/#properties-for-device-type-tunnels
network:
  renderer: networkd
  tunnels:
    ${VXLAN_NAME}:
      mode: vxlan
      id: ${VXLAN_ID}
      link: ${VTEP_DEV}
      mtu: 8950
      port: 4789
      local: ${VTEP1_ADDR}
      remote: ${VTEP2_ADDR}
  bridges:
    ${BRIDGE}:
      interfaces:
        - ${VXLAN_NAME}
EOF
sudo chmod 600 /etc/netplan/11-${VXLAN_NAME}-config.yaml
```

Apply the change to create the bridge and VxLAN:
```sh
sudo netplan apply
```

## Create the VMs
### Clone VM
Start by cloning a valid VM. Make sure the template VM is shutdown:
```sh
virsh shutdown ${ORIGINAL}
for NEW in "${!newVM[@]}"
do
  # Create the new directory
  sudo install -v -d -g libvirt -o libvirt-qemu /var/lib/libvirt/images/${NEW}

  # Clone the VM
  sudo virt-clone --connect qemu:///system \
  --original ${ORIGINAL} --name ${NEW} \
  --file /var/lib/libvirt/images/${NEW}/${NEW}.qcow2

  # Change permission
  sudo chown libvirt-qemu:libvirt /var/lib/libvirt/images/${NEW}/${NEW}.qcow2
done
```

### Customize the VMs
Once you have cloned the VM, you can customize the new virtual machines with `virt-sysprep` utility. Make sure the utility is installed with the command `sudo apt install guestfs-tools`
```sh
OPERATIONS=$(virt-sysprep --list-operations | egrep -v 'lvm-uuids|fs-uuids|ssh-hostkeys|ssh-userdir' | awk '{ printf "%s,", $1}' | sed 's/,$//')

for NEW in "${!newVM[@]}"
do
  sudo virt-sysprep -d ${NEW} \
  --hostname ${NEW}.kloud.lan \
  --enable ${OPERATIONS} \
  --keep-user-accounts daniel \
  --run-command "sed -i \"s/127.0.1.1.*/127.0.1.1 ${NEW}/\" /etc/hosts" \
  --run-command "sed -i \"s/127.0.0.1 localhost/127.0.0.1 localhost ${NEW}/\" /etc/hosts" \
  --run-command "sed -i \"s/10.103.1.10/${newVM[${NEW}]}/\" /etc/netplan/50-cloud-init.yaml" \
  --run-command "sed -i \"s/10.103.1.1/${defaultGateway}/\" /etc/netplan/50-cloud-init.yaml"
done
```

### Attach VM to bridge
> [!NOTE]  
> You can skip this section if your VM template has the correct bridge network configured.

Attach the VM to the bridge network:
```sh
cat <<EOF >net.xml
<interface type='bridge'>
  <source bridge="${BRIDGE}"/>
  <model type='virtio'/>
  <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0' multifunction='on'/>
</interface>
EOF

for NEW in "${!newVM[@]}"
do
  virsh update-device ${NEW} net.xml
done

rm -f net.xml
```

## Start the VMs
Start the VMs.

> [!NOTE]  
> By default the VMs won't auto start. I added the line `virsh autostart ${NEW}` for them to start automaticaly.

```sh
#!/bin/bash
for NEW in "${!newVM[@]}"
do
  printf "Starting VM %s\n" "${NEW}"
  virsh start ${NEW}
  virsh autostart ${NEW}
done
```

## Add SNAT
You can add a source NAT rule for the VMs to access the Internet via the node's default gateway. This command configure the NAT.

IF THE FILE `/etc/iptables/rules.v4` EXISTS use this command:
```sh
sudo sed -i -e '/# Forward traffic.*/a\' -e "-A POSTROUTING -s ${localSubnet}/${subnetMask} -o eth0 -j MASQUERADE" /etc/iptables/rules.v4
```

If the file `/etc/iptables/rules.v4` doesn't exist, use the following:
```sh
cat <<EOF | sudo tee -a /etc/iptables/rules.v4
# nat Table rules
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic from VM subnets through eth0.
-A POSTROUTING -s ${localSubnet}/${subnetMask} -o eth0 -j MASQUERADE

# don't delete the 'COMMIT' line or these nat table rules won't be processed
COMMIT
EOF
```

You can apply the rules with the command:
```sh
sudo iptables-restore /etc/iptables/rules.v4
```

# Cleanup
Cleanup stuff.
```sh
unset ORIGINAL
unset newVM
unset localSubnet
unset subnetMask
unset defaultGateway
unset localBroadcast
unset BRIDGE
unset VXLAN_ID
unset VXLAN_NAME
unset VTEP1_ADDR
unset VTEP2_ADDR
unset VTEP_DEV
```

# Destroy the VMs (Optional)
If you want to completly destroy the VMs and remove the disk image, use the script below:
```sh
for VM in "${!newVM[@]}"
do
  virsh shutdown ${VM}
  STATUS=$(virsh domstate ${VM})
  while ([ "${STATUS}" != "shut off" ] )
  do
    STATUS=$(virsh domstate ${VM})
    printf "   Status of VM [%s] is: %s\n" "${VM}" "${STATUS}"
    sleep 2
  done
  printf "[%s] is shutdown: %s\n" "${VM}" "${STATUS}"
  sudo virsh undefine ${VM} --remove-all-storage --wipe-storage
done
```

# Troubleshoot
Show bridge details:
```sh
ip -d link show br_etcd_1
```

Show port in bridge:
```sh
sudo brctl show br_etcd_1
```

```sh
ip -brief link
```

# BUGS
If you get this message `Cannot call Open vSwitch: ovsdb-server.service is not running.` after `sudo netplan apply` then apply this patch on the file `/usr/share/netplan/netplan/cli/commands/apply.py`

The patch just checks if **Open vSwitch** is active.
```
             if exit_on_error:
                 sys.exit(1)
         except OvsDbServerNotRunning as e:
- logging.warning('Cannot call Open vSwitch: {}.'.format(e))
+ if utils.systemctl_is_active('ovsdb-server.service'):
+   logging.warning('Cannot call Open vSwitch: {}.'.format(e))
```