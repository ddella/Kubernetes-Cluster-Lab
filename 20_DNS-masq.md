# DOES NOT WORK AS EXPECTED

# DNS
Configure a DNS server for a specific domain

## Install dnsmasq
```sh
sudo nala install dnsmasq
```

## Configure custom DNS
```sh
cat <<EOF | sudo tee /etc/dnsmasq.d/custom-dns
server=/kloud.lan/192.168.13.10
EOF
```

## Restart the service
```sh
sudo systemctl restart dnsmasq.service
sudo systemctl status dnsmasq.service
```


# Disable IPv6 (Optional)
I've decided to disable IPv6. This is optional.
```sh
sudo tee /etc/sysctl.d/60-disable-ipv6.conf<<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
# ??? 
net.ipv6.conf.virbr1.accept_ra = 0
net.ipv6.conf.virbr1.autoconf = 0
EOF

# sudo sysctl --system
sudo sysctl -p /etc/sysctl.d/60-disable-ipv6.conf
``` 

# Disable IPv6
```sh
sudo vi /etc/default/grub
```

Add `ipv6.disable=1` to the line `GRUB_CMDLINE_LINUX_DEFAULT`. See below the final result:
```
GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"
```

```sh
sudo update-grub
sudo init 6
```


daniel@pve2 ~ $ sudo ls -la /etc/netplan/
total 56
drw-------   2 root root  4096 Nov 19 11:34 .
drwxr-xr-x 124 root root 12288 Nov 19 11:42 ..
-rw-------   1 root root  1065 Nov 19 11:34 00-installer-config.yaml
-rw-------   1 root root   209 Nov 17 16:40 10-br_bastion_1-config.yaml
-rw-------   1 root root   206 Nov 15 18:18 10-br_etcd_1-config.yaml
-rw-------   1 root root   208 Nov 16 19:02 10-br_master_1-config.yaml
-rw-------   1 root root   208 Nov 15 18:19 10-br_worker_1-config.yaml
-rw-------   1 root root   453 Nov 17 16:41 11-bastion-10100-config.yaml
-rw-------   1 root root   445 Nov 14 19:23 11-etcd-10103-config.yaml
-rw-------   1 root root   450 Nov 16 19:02 11-master-10101-config.yaml
-rw-------   1 root root   382 Nov 14 15:55 11-vxlans-config.yaml.bak
-rw-------   1 root root   450 Nov 15 10:15 11-worker-10102-config.yaml

sudo journalctl -eu libvirtd

cat <<EOF | sudo tee /etc/NetworkManager/dnsmasq.d/libvirt.conf
server=/kloud.lan/192.168.13.10
EOF

ubuntu-10
ubuntu-11
temp-ubuntu-1nic-2204
