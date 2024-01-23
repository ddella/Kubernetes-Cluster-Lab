# Kernel Upgrade

## Installing latest Linux kernel
If you want to test the latest stable Linux kernel, you can follow the steps below.

Make sure you are up to date:
```sh
sudo nala update && sudo nala -y upgrade
```

> [!IMPORTANT]  
> You need the package `gnupg2` or you'll get a key error when installing the Kernel.

The Ubuntu Mainline Kernel script (available on [GitHub](https://github.com/pimlie/ubuntu-mainline-kernel.sh)).
Use this Bash script for Ubuntu (and derivatives such as LinuxMint) to easily (un)install kernels from the [Ubuntu Kernel PPA](http://kernel.ubuntu.com/~kernel-ppa/mainline/).
```sh
curl -LO https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
```

Make the file executable and move it to `/usr/local/bin/`:
```sh
sudo install -v --group=adm --owner=root --mode=755 ubuntu-mainline-kernel.sh /usr/local/bin/
rm ubuntu-mainline-kernel.sh
```

>I changed the owner for the directory `/usr/local/bin/`. Adjust to your environment.

To install the latest Linux kernel package, which is available in the [Ubuntu Kernel repository](https://kernel.ubuntu.com/~kernel-ppa/mainline/), use the command:
```sh
sudo ubuntu-mainline-kernel.sh -i
```

After the installation, reboot to use the new kernel:
```sh
sudo init 6
```

## Cleanup Kernels
After a Kernel upgrade, please do the following. That will fix the warning:`There are broken packages that need to be fixed!`:
```sh
sudo apt --fix-broken install
sudo nala update && sudo nala upgrade
```

> [!WARNING]  
> Leave at least one Kernel for production 😉

You can delete the old kernels to free disk space. You should always keep two versions of Kernel but this is a lab and I don't have a lot of disk space.

Check what Kernel(s) is(are) installed:
```sh
sudo dpkg --list | egrep 'linux-image|linux-headers|linux-modules'
```

Remove old kernels listing from the preceding step with the command:
```sh
sudo apt purge $(dpkg-query --show 'linux-headers-*' | cut -f1 | grep -v "$(uname -r | cut -f1 -d '-')")
sudo apt purge $(dpkg-query --show 'linux-modules-*' | cut -f1 | grep -v "$(uname -r | cut -f1 -d '-')")
# The last one should not be required
# sudo apt purge $(dpkg-query --show 'linux-image-*' | cut -f1 | grep -v "$(uname -r | cut -f1 -d '-')")
```

After removing the old kernel, update the grub2 configuration:
```sh
sudo update-grub2
```

> [!IMPORTANT]  
> I had some issue in the past with the [Ubuntu Kernel PPA](http://kernel.ubuntu.com/~kernel-ppa/mainline/). The site had been done for weeks and when it came back the Kernels were not updated. Anothe solution is to use [linux-zabbly](https://ubuntuhandbook.org/index.php/2023/08/install-latest-kernel-new-repository/)  
