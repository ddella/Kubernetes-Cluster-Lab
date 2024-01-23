#

## Add node role
I like to have `ROLES` with `worker` for all my worker nodes. Just add an empty label `node-role.kubernetes.io/worker` on your worker nodes:
```sh
for i in {1..6}; do kubectl label node k8s1worker${i}.kloud.lan node-role.kubernetes.io/worker=''; done
```

## Check New Worker Node
On any master node, verify that the new worker node has joined the party 🎉
```sh
kubectl get nodes -o=wide
```

Output:
```
NAME                    STATUS     ROLES           AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION   CONTAINER-RUNTIME
k8s1master1.kloud.lan   NotReady   control-plane   51m     v1.28.4   10.101.1.101   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1master2.kloud.lan   NotReady   control-plane   49m     v1.28.4   10.101.1.102   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1master3.kloud.lan   NotReady   control-plane   48m     v1.28.4   10.101.1.103   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1master4.kloud.lan   NotReady   control-plane   48m     v1.28.4   10.101.1.201   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1master5.kloud.lan   NotReady   control-plane   47m     v1.28.4   10.101.1.202   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1master6.kloud.lan   NotReady   control-plane   47m     v1.28.4   10.101.1.203   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1worker1.kloud.lan   NotReady   worker          10m     v1.28.4   10.102.1.101   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1worker2.kloud.lan   NotReady   worker          8m38s   v1.28.4   10.102.1.102   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1worker3.kloud.lan   NotReady   worker          8m21s   v1.28.4   10.102.1.103   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1worker4.kloud.lan   NotReady   worker          8m12s   v1.28.4   10.102.1.201   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1worker5.kloud.lan   NotReady   worker          8m2s    v1.28.4   10.102.1.202   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
k8s1worker6.kloud.lan   NotReady   worker          7m25s   v1.28.4   10.102.1.203   <none>        Ubuntu 22.04.3 LTS   6.6.1-zabbly+    containerd://1.7.9
```

>Node should be `Ready` if you installed a `CNI `.

