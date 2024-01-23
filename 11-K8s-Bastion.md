# Bastion Hosts

## Copy Kubernetes configuration file
If you use a bastion host, you can copy the `admin.conf` file from a master node with the command:
```sh
rsync --mkpath --rsync-path="sudo rsync" daniel@k8s1master1:/etc/kubernetes/admin.conf $HOME/.kube/config
```

## Configure Kubernetes Repo
> **Note**
>Kubernetes has two different package repositories starting from August 2023. The Google-hosted repository is deprecated and it's being replaced with the Kubernetes (community-owned) package repositories. The Kubernetes project strongly recommends using the Kubernetes community-owned package repositories, because the project plans to stop publishing packages to the Google-hosted repository in the future.

>There are some important considerations for the Kubernetes package repositories:
>- The Kubernetes package repositories contain packages beginning with those Kubernetes versions that were still under support when the community took over the package builds. This means that anything before v1.24.0 will only be available in the Google-hosted repository.
>- There's a dedicated package repository for each Kubernetes minor version. When upgrading to to a different minor release, you must bear in mind that the package repository details also change.

Install packages dependency:
```sh
sudo nala install apt-transport-https ca-certificates
```

Download the public signing key for the Kubernetes package repositories. The same signing key is used for all repositories so you can disregard the version in the URL:
```sh
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Add the Kubernetes repository:
```sh
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

[Changing The Kubernetes Package Repository](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/)  


## Install `kubeadm` and `kubectl`
- Update the Ubuntu package index
- Install `kubeadm` and `kubectl`
- Pin their version:

```sh
sudo nala update
sudo nala install kubeadm kubectl
sudo apt-mark hold kubeadm kubectl kubelet
```

Verify K8s version:
```sh
kubectl version --output=yaml
kubeadm version --output=yaml
```

>You'll get the following error message from **kubectl**: `The connection to the server localhost:8080 was refused - did you specify the right host or port?`. We haven't installed anything yet. It's a normal problem 😂!

Enable `kubectl` and `kubeadm` autocompletion for Bash:
```sh
sudo kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
sudo kubeadm completion bash | sudo tee /etc/bash_completion.d/kubeadm > /dev/null
```

After reloading your shell, `kubectl` and `kubeadm` autocompletion should be working.
```sh
source ~/.bashrc
```
