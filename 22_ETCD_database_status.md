# Check ETCD database status on Bastion host

## Copy certificates
Copy the `etcd` root CA and the client certificate/private key. In my case I had done everything on the first `etcd` node:
```sh
scp daniel@k8s1etcd1:/home/daniel/etcd/etcd-ca.crt .
scp daniel@k8s1etcd1:/home/daniel/etcd/k8s1master1.crt .
scp daniel@k8s1etcd1:/home/daniel/etcd/k8s1master1.key .
```

> [!NOTE]  
> The client certificate/private key are named `k8s1master1.{crt,key}`. Not the best name so far 😁

## Export Variables
Export variables for `etcdctl` instead of adding switches
```sh
export ETCDCTL_ENDPOINTS=https://k8s1etcd1.kloud.lan:2379,https://k8s1etcd2.kloud.lan:2379,https://k8s1etcd3.kloud.lan:2379,https://k8s1etcd4.kloud.lan:2379,https://k8s1etcd5.kloud.lan:2379,https://k8s1etcd6.kloud.lan:2379
export ETCDCTL_CACERT=$HOME/etcd/etcd-ca.crt
export ETCDCTL_CERT=$HOME/etcd/k8s1master1.crt
export ETCDCTL_KEY=$HOME/etcd/k8s1master1.key
```

## Check Cluster status
To execute the next command, you can be on any host that:
- can reach the `etcd` servers on port `TCP/2379`
- has the client certificate, the CA certificate and private key

And now it's a lot easier
```sh
etcdctl --write-out=table member list
etcdctl --write-out=table endpoint status
etcdctl --write-out=table endpoint health
```
