# SSH Keys

## Define variables
This is the array of all my VMs. They are all on my internal DNS.
```sh
unset arrVMs
arrVMs=(
  "k8s1bastion1"
  "k8s1bastion2"
  "k8s1vrrp1"
  "k8s1vrrp2"
  "k8s1master1"
  "k8s1master2"
  "k8s1master3"
  "k8s1master4"
  "k8s1master5"
  "k8s1master6"
  "k8s1worker1"
  "k8s1worker2"
  "k8s1worker3"
  "k8s1worker4"
  "k8s1worker5"
  "k8s1worker6"
  "k8s1etcd1"
  "k8s1etcd2"
  "k8s1etcd3"
  "k8s1etcd4"
  "k8s1etcd5"
  "k8s1etcd6"
)
MYPASSWORD=<PASSWORD>
```

## Reset SSH Key
The following actions are done on the remote host:

- Empty the "authorized_keys" file on the remote host
- Generate new priv/pub SSH key pair on the remote host

```sh
for VM in "${arrVMs[@]}"
do
  sshpass -p ${MYPASSWORD} ssh -o StrictHostKeyChecking=no ${USER}@${VM} "cp /dev/null .ssh/authorized_keys >/dev/null 2>&1"
  sshpass -p ${MYPASSWORD} ssh -o StrictHostKeyChecking=no ${USER}@${VM} "ssh-keygen -q -t ecdsa -N '' -f ~/.ssh/id_ecdsa <<<y >/dev/null 2>&1"
  printf "New private/public SSH key pair for %s\n" "${VM}"
done
```

> [!IMPORTANT]  
> You do this only once. In this example, I did this on `k8s1bastion1` only.

## SSH without password
You will need to install the `sshpass` package with the command `sudo apt install sshpass`.

- Copy you public key to the "authorized_keys" file on the remote host so you don't need to enter the password
- This will populate your local `known_hosts` so you won't need to answer `yes` to accept the public key for your first login.

```sh
for VM in "${arrVMs[@]}"
do
  sshpass -p ${MYPASSWORD} ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ecdsa.pub ${VM}
  ssh-keyscan ${VM} >> ~/.ssh/known_hosts
  printf "New SSH key for %s\n" "${VM}"
done
```

> [!IMPORTANT]  
> This needs to be done on every hosts that might act as a `bastion` host.


# `sshpass` on macOS

## Install sshpass
Install `sshpass` on my local `~/bin` directory:
```sh
curl -LO https://sourceforge.net/projects/sshpass/files/latest/download/sshpass/1.10/sshpass-1.10.tar.gz
tar zxvf sshpass-1.10.tar.gz
cd sshpass-1.10
./configure
make
install -g staff -o daniel sshpass $HOME/bin/.
```

## Set SSH without password
Set SSH without password from my macOS:
```sh
for VM in "${arrVMs[@]}"
do
  sshpass -p ${MYPASSWORD} ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ecdsa.pub ${VM}
  printf "New SSH key for %s\n" "${VM}"
done

unset MYPASSWORD
```
