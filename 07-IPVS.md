# Install IPVS
Install `ipvs` on Ubuntu 22.04. I'm using `nala`. If you don't have it, use `apt`:
```sh
sudo nala update
sudo nala install ipvsadm ipset
```

# Kernel Modules
## Ensure `IPVS` required kernel module are loaded at boot time.
```sh
cat <<EOF | sudo tee /etc/modules-load.d/ipvs.conf > /dev/null
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF
```

## Load the modules and check for any errors:
```sh
sudo systemctl restart systemd-modules-load.service
sudo systemctl status systemd-modules-load.service
```

## Check if modules are loaded
```sh
# to check loaded modules, use
lsmod | grep -e ip_vs -e nf_conntrack
# or
cut -f1 -d " "  /proc/modules | grep -e ip_vs -e nf_conntrack
```
