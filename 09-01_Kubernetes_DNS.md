# Kubernetes DNS
In this tutorial I'll focus on exposing Kubernetes cluster internal resources, like services to the outside world. I already did the pure IP connectivity with Cilium BGP. This tutorial is NOT about `NodePort` type Services but about `LoadBalancer` controllers. We'll focus on one crucial piece of network connectivity which glues together the dynamically-allocated external IP with a static customer-defined hostname -  the DNS. We'll show how to expose external DNS in Kubernetes and introduce a new CoreDNS plugin that can be used for dynamic discovery and resolution of multiple types of external Kubernetes resources.

## Before we begin

|dnsDomain|Description|
|---------|-----------|
|`cluster.local`|Kubernetes Cluster dnsDomain|
|`kloud.lan`|Main dnsDomain|
|`k8s1-prod.kloud.lan`|SubDomain for Kubernetes services|

|CIDR|Description|
|---------|-----------|
|`100.64.0.0/16`|Kubernetes Pods CIDR|
|`198.18.0.0/16`|Kubernetes Services CIDR for Cluster IP|
|`198.19.0.0/16`|Kubernetes Services CIDR for External IP|

|DNS Server|Description|Software|
|---|-----------|--------|
|192.168.13.10|DNS VRRP for `kloud.lan`|Keepalived|
|192.168.13.11|DNS1 for `*.kloud.lan`|Bind 9|
|192.168.13.12|DNS2 for `*.kloud.lan`|Bind 9|

> [!IMPORTANT]  
> The IP `192.168.13.10` is the source IP for DNS request made from the active DNS server. Keep this in mind for firewall rules and `acl`

I will use this service for testing throughout this tutorial:
```
kubectl get services -n linkerd-viz web
NAME   TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
web    LoadBalancer   198.18.0.245   198.19.0.5    8084/TCP,9994/TCP   5d
```

Get the Pods and Cluster IP Services CIDR:
```sh
printf "Pods CIDR: %s\n" $(kubectl cluster-info dump | grep -m 1 -Po '(?<=--cluster-cidr=)[0-9.\/]+')
printf "Service CIDR (Cluster IP): %s\n" $(kubectl cluster-info dump | grep -m 1 -Po '(?<=--service-cluster-ip-range=)[0-9.\/]+')
```

## Static Routes
If you have a macOS and want to access your Kubernetes Cluster, you'll need static routes
```sh
# The Pods CIDR of the Kubernetes Cluster
sudo route -n add -net 100.64.0.0/16 192.168.13.91
# The Load-Balancer services CIDR of the Kubernetes Cluster
sudo route -n add -net 198.19.0.0/16 192.168.13.91
```

On Linux (my local Bind DNS servers):
```sh
# The Pods CIDR of the Kubernetes Cluster
sudo ip route add 100.64.0.0/16 via 192.168.13.91
# The Load-Balancer services CIDR of the Kubernetes Cluster
sudo ip route add 198.19.0.0/16 via 192.168.13.91
```

> [!WARNING]  
> You should **never** need a route to the Pods CIDR. I added the route to `100.64.0.0/16` for testing purposes.

## External Kubernetes Resources
The various types of external Kubernetes resources are:
- NodePort
- LoadBalancer

This tutorial is **NOT** about Kubernetes `NodePort` service but focuses on `LoadBalancer`.

The `LoadBalancer` service is one of the most common ways of exposing services to the external world. It's what most Cloud Provider uses. This service type requires an extra controller that will be responsible for IP address allocation and delivering traffic to the Kubernetes nodes. This function can be implemented by cloud load-balancers or in my case, with my "OnPrem" Kubernetes Cluster by Cilium CNI.

## What is CoreDNS
CoreDNS is a open source DNS server written in Go. It can be used in a multitude of environments because of its flexibility. CoreDNS is the internal DNS for Kubernetes and is licensed under the Apache License Version 2.

## CoreDNS
Kubernetes expose a service named `kube-dns` with the 10th IP in the Pods CIDR. It doesn't by default expose an `EXTERNAL-IP`.
```sh
kubectl get svc kube-dns -n kube-system
```

Output:
```
NAME       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   198.18.0.10   <none>        53/UDP,53/TCP,9153/TCP   23d
```

You can get the configuration, ConfigMap, of CoreDNS with the command:
```sh
kubectl get configmap coredns -n kube-system -o yaml
```

Output:
```
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
kind: ConfigMap
```

You can edit the configuration with the command:
```sh
kubectl -n kube-system edit configmap coredns
```

You can get the `kube-dns` service information with the command:
```sh
kubectl get svc kube-dns -n kube-system
```

Output:
```
NAME       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   198.18.0.10   <none>        53/UDP,53/TCP,9153/TCP   23d
```

You can check the logs of CoreDNS with the command:
```sh
kubectl logs -n kube-system -l k8s-app=kube-dns
```

> [!NOTE]  
> Add `-f` to get real time logs

You can get the CoreDNS pods (you should have 2 Pods):
```sh
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

You can get the nodes that are hosting the CoreDNS pods:
```sh
kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].spec.nodeName}{"\n"}'
```
# Before you begin
Create a simple Pod to use as a test environment. This Pod has the necessary tools for client DNS request, like `dig` and `nslookup`. This Pod will be used to test DNS query inside our Kubernetes Cluster.
```sh
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: dnsutils
  labels:
    name: dnsutils
---
apiVersion: v1
kind: Pod
metadata:
  name: dnsutils
  namespace: dnsutils
spec:
  containers:
  - name: dnsutils
    image: registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3
    command:
      - sleep
      - "infinity"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF
```

## Test the Pod
Check that `dig` is installed:
```sh
kubectl exec -it dnsutils -n dnsutils -- dig -v
```

Output:
```
DiG 9.18.19
```

## Services

### DNS "A" query
If you make a DNA query, from the test Pod, on a service it will return the `CLUSTER-IP`
```sh
kubectl exec -it dnsutils -n dnsutils -- dig +short kube-dns.kube-system.svc.cluster.local
```

Output:
```
198.18.0.10
```

### DNS "SRV" query
The DNS "service" (SRV) record specifies a host and port for specific services. Let's check the port number for `kube-dns`:
```sh
kubectl exec -it dnsutils -n dnsutils -- dig srv kube-dns.kube-system.svc.cluster.local +short
```

Output
```
0 33 53 kube-dns.kube-system.svc.cluster.local.
0 33 9153 kube-dns.kube-system.svc.cluster.local.
```

If you know what service, you can query it directly:
```sh
kubectl exec -it dnsutils -n dnsutils -- dig +short srv _dns._udp.kube-dns.kube-system.svc.cluster.local
kubectl exec -it dnsutils -n dnsutils -- dig +short srv _dns-tcp._tcp.kube-dns.kube-system.svc.cluster.local
kubectl exec -it dnsutils -n dnsutils -- dig +short srv _metrics._tcp.kube-dns.kube-system.svc.cluster.local
```

Output for each command above, in order:
```
0 100 53 kube-dns.kube-system.svc.cluster.local.
0 100 53 kube-dns.kube-system.svc.cluster.local.
0 100 9153 kube-dns.kube-system.svc.cluster.local.
```

# CoreDNS Zone Transfer (Don't do this. For information ONLY)
Kubernetes, by default, registers all the Pods and services using the `cluster.local` DNS domain or whatever has been configured by `kubeamd` when the cluster was bootstrapped. At some point we might want to be able to take a look at this zone. Zone transfers are going to be restricted by default:

```sh
kubectl exec -it dnsutils -n dnsutils -- dig axfr cluster.local
```

Output:
```
; <<>> DiG 9.9.5-9+deb8u19-Debian <<>> axfr cluster.local
;; global options: +cmd
; Transfer failed.
```

We can configure CoreDNS to allow zone transfers. To do so we'll have to edit the CoreDNS `ConfigMap` in the `kube-system` namespace. Allowing zone transfers is configured using the transfer block. For example, to allow zone transfers to any client, add the following to the CoreDNS `ConfigMap`:
```sh
kubectl edit configmap coredns -n kube-system
```

Add the following lines after the `loadbalance` command.
```
[...]
        loadbalance
        acl {
          allow type AXFR net 100.64.0.0/10
          allow type IXFR net 100.64.0.0/10
          block type AXFR net *
          block type IXFR net *
        }
        transfer {
          to *
        }
```

> [!NOTE]  
> CoreDNS is going to automatically reload it's configuration, it can take up to 1-2 minutes, be patient.
> In case you can't wait: `kubectl delete pods -n kube-system -l k8s-app=kube-dns` 😉

You can check the logs, with the command `kubectl logs -n kube-system -l k8s-app=kube-dns -f`, for the following message to know when the configuration has been applied.
```
[INFO] Reloading
[INFO] plugin/reload: Running configuration SHA512 = 02602b45871409250596ab0f8c2225719378613697a749ff760303b1a6ca8d01a7df77cd8f9e390c0e068a4ec2019ec63fd67a64abf9ffa306fe124edfc0af78
[INFO] Reloading complete
```

> [!IMPORTANT]  
> You need to have 2 messages because there's 2 `kube-dns` Pods

After 1-2 minutes, you should see all your DNS entries in your Kubernetes cluster with the command:
```sh
kubectl exec -it dnsutils -n dnsutils -- dig axfr cluster.local
```

If you test from a Kubernetes node (master or worker node), use the IP address of you Kubernetes Cluster's DNS `ClusterIP`. In my cluster it's `198.18.0.10`:
```sh
dig @198.18.0.10 axfr cluster.local
```

> [!NOTE]  
> In my setup, the source IP address of the DNS queries are the Cilium CNI interface `cilium_host@cilium_net`, since I'm using Cilium as my CNI. I will never be sourced from your local LAN. This is why in the `ACL` I have only the Pods CIDR.

# CoreDNS world reachable
I wanted to make CoreDNS world reachable by assigning an `EXTERNAL IP` to the `kube-dns` service. I already had a Cilium IP Pool for the namespace `kube-system`. Since this is the DNS service, we need to have a **static IP** for the service. Services can request specific IPs **whithin the** `IPPool`. The way of requesting specific IPs is to use the annotation `io.cilium/lb-ipam-ips` in the case of Cilium LB IPAM. This annotation takes a comma-separated list of IP addresses, allowing for multiple IPs to be requested at once. The service selector of the IP Pool still applies.

> [!IMPORTANT]  
> Requested IPs will not be allocated or assigned if the services don't match the pool's selector.
> The value of the key "io.cilium/lb-ipam-ips" is a string not an array.

Here's the steps:
- assign a static IP for the `EXTERNAL-IP`
- convert the DNS service to type `LoadBalancer`

```sh
# Request specific IP for DNS service
kubectl patch services -n kube-system kube-dns -p '{"metadata":{"annotations":{"io.cilium/lb-ipam-ips":"198.19.0.30"}}}'
# Change type of service "kube-dns" from "ClusterIP" to "LoadBalancer". This needs to be an atomic patch or you'll get a NodePort configured
kubectl patch services -n kube-system kube-dns --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"},{"op":"add","path":"/spec/allocateLoadBalancerNodePorts","value":false}]'
```

```sh
kubectl get svc -n kube-system kube-dns
```

Before the modification:
```
NAME       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   198.18.0.10   <none>        53/UDP,53/TCP,9153/TCP   43d

```

After the modification:
```
kubectl get svc -n kube-system kube-dns
NAME             TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                  AGE
kube-dns         LoadBalancer   198.18.0.10    198.19.0.30   53/UDP,53/TCP,9153/TCP   43d
```

> [!NOTE]  
> I'm using Cilium BGP and I advertise all `EXTERNAL-IP` from service type `Load-Balancer`. IP `198.19.0.30` is known outside the Kubernetes cluster.

## Source IP
Applications running in a Kubernetes cluster find and communicate with each other, and the outside world, through the Service abstraction. Packets sent to Services with `Type=LoadBalancer` are source NAT'd by default, because all schedulable Kubernetes nodes in the Ready state are eligible for load-balanced traffic. So if packets arrive at a node without an endpoint, the system proxies it to a node with an endpoint, replacing the source IP of the packet with the IP of the node.

In my case, that's not desirable because I want to have an ACL for all DNS query that comes from outside the Kubernetes Cluster. Only my main DNS's can query Kubernetes CoreDNS.
```sh
kubectl patch services -n kube-system kube-dns -p '{"spec":{"externalTrafficPolicy":"Local"}}'
```

You should immediately see the `service.spec.healthCheckNodePort` field allocated by Kubernetes:
```sh
kubectl get services -n kube-system kube-dns -o yaml | grep -i healthCheckNodePort
```

The output is similar to this:
```
  healthCheckNodePort: 31033
```

The configuration of the `kube-dns` service looks like this after the patch:
```
[...]
spec:
  allocateLoadBalancerNodePorts: false
[...]
  externalTrafficPolicy: Local
  healthCheckNodePort: 31003
  internalTrafficPolicy: Cluster
[...]
```

> [!IMPORTANT]  
> This assumes that you have full routing inside and outside your Kubernetes Cluster

Let's make sure that health checking still works. Get the nodes that run CoreDNS Pods:
```sh
kubectl get pod -n kube-system -l k8s-app=kube-dns --output=custom-columns='NODE:.spec.nodeName' --no-headers
```

From one of the nodes above, use curl to fetch the `/healthz` endpoint :
```sh
curl http://localhost:31003/healthz
```

Output:
```
{
	"service": {
		"namespace": "kube-system",
		"name": "kube-dns"
	},
	"localEndpoints": 1,
	"serviceProxyHealthy": true
}
```

## TEST
Now I can query Kubernetes CoreDNS from anywhere.

Get the IP address of the service:
```sh
dig @198.19.0.30 +short web.linkerd-viz.svc.cluster.local
```

It is important to notice that we received the `ClusterIP` instead of the `EXTERNAL-IP`. Cilium BGP advertise only the `EXTERNAL-IP` address, as a `/32`. We need to have CoreDNS return the `EXTERNAL-IP` of a service. We'll fix this below.
```
198.18.0.245
```

# Bind9
When I bootstrapped my Kubernetes Cluster I didn't change the default domain name, `cluster.local`, a mistake that I will **never** make again 😉 We need to forward all DNS request for domain `cluster.local` to the Kubernetes CoreDNS LoadBalancer service external IP address `198.19.0.30` that I just configured above. Unfortunatly that was not possible since the domain name `.local` is a special-use domain name for hostnames in local area networks that can be resolved via the Multicast DNS name resolution protocol. If you try `dig ...` you'll get the following warning:

```
;; WARNING: .local is reserved for Multicast DNS
```

I decided to use the domain `k8s1-prod.kloud.lan` outside my Kubernetes Cluster to resolve services inside the cluster. The trick is to forward all DNS request for domain `k8s1-prod.kloud.lan` to the `EXTERNAL-IP` of CoreDNS in the Kubernetes Cluster. Since this is a subdomain of my external domain, the only thing I needed to do is:

- Define a sub-domain of you main domain in my Kubernetes Cluster. My local domain name is `kloud.lan` and my subdomain for my Kubernetes Cluster is `k8s1-prod.kloud.lan`.
- Edit the file `/etc/bind/db.kloud.lan` in your DNS server. I'm using BIND9, your milage may vary 😉. Basically I'm sending every request for `*.k8s1-prod.kloud.lan` to my cluster `kube-dns` service. That's it. There's nothing else to add/modify even if you add more services.

## Non Forwarder
If your Bind DNS is a `non-forwarder`, meaning it is a recursive DNS that handles all the queries and uses the root, TLD, ... then this is for you. Just add this to your main domain.

file `/etc/bind/db.kloud.lan`
```
; ----------------------------------------------
; sub-domain definitions for k8s1-prod.kloud.lan
; ---------------------------------------------
$ORIGIN k8s1-prod.kloud.lan.
; we define one name server for the sub-domain
; which is the Kubernetes DNS Service IP address
@               IN NS     ns.k8s1-prod.kloud.lan.

; sub-domain address records for name server only - glue record
ns              IN A      198.19.0.30 ; 'glue' record
```

## Forwarder
If you Bind DNS is a forwarder then the configuration above won't actually work. Let's say you forward everything to Cloudflare with DoT enabled like this:
file `/etc/bind/named.conf.options`
```
  forwarders port 853 tls cloudflare-DoT {
    1.1.1.1;
    1.0.0.1;
  };
```

You need to **ADD** the following configuration. You keep the subdomain configuration in the section `Non Forwarder` above.

Create a new zone for your Kubernetes dnsDomain (subdomain of your main domain) and forward everything to the `EXTERNAL-IP` og your `kube-dns` Kubernetes service.
file `/etc/bind/named.conf.local`
```
// Forward all request for "*.k8s1-prod.kloud.lan" to DNS 198.19.0.30
zone "k8s1-prod.kloud.lan" {
    type forward;
    forward only;
    forwarders { 198.19.0.30; };
};
```

> [!IMPORTANT]  
> Don't forget to adjust the serail number in case you have a secondary DNS server
> Add the configuration at the **bottom**, since `$ORIGIN` has been modified

Restart `bind9` and make sure it's running:
```sh
sudo systemctl restart bind9
sudo systemctl status bind9
```

We're not done yet 😀 It won't work since we can't ask CoreDNS to resolve anything for domain `k8s1-prod.kloud.lan`. The easiest solution is:

Edit CoreDNS ConfigMap, with the command `kubectl edit configmap coredns -n kube-system`, and add a the plugin `k8s_external`. This will :
- return the `EXTERNAL-IP` for the service you query instead of the `Cluster IP`
- and you won't need any `rewrite` of domains (query and answer)

Configuration with an `ACL` (you remember we removed SNAT earlier 😉)
```yaml
[...]
    .:53 {
        k8s_external k8s1-prod.kloud.lan
        acl k8s1-prod.kloud.lan {
          allow net 192.168.13.10/32 192.168.13.11/32 192.168.13.12/32
          block
        }
[...]
```

Here's a query from a Linux client outside the Kubernetes Cluster. 
```sh
dig web.linkerd-viz.k8s1-prod.kloud.lan
```

Fantastic, it works and it returns the `EXTERNAL-IP`. Look at the server `SERVER: 127.0.0.53#53`. The request was made on Linux and it's using `systemd-resolve`:
```
; <<>> DiG 9.18.18-0ubuntu0.22.04.1-Ubuntu <<>> web.linkerd-viz.k8s1-prod.kloud.lan
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 9664
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 65494
;; QUESTION SECTION:
;web.linkerd-viz.k8s1-prod.kloud.lan. IN	A

;; ANSWER SECTION:
web.linkerd-viz.k8s1-prod.kloud.lan. 5 IN A	198.19.0.5

;; Query time: 3 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Tue Jan 02 11:35:19 EST 2024
;; MSG SIZE  rcvd: 80
```

Make sure that inside our Kubernetes Cluster we still receive the `Cluster IP`. We don't want the traffic inside the Cluster to go outside and come back:
```sh
kubectl exec -it dnsutils -n dnsutils -- dig web.linkerd-viz.svc.cluster.local
```

Output, look at the server `SERVER: 198.18.0.10#53`, it's the `kube-dns` service:
```
; <<>> DiG 9.9.5-9+deb8u19-Debian <<>> web.linkerd-viz.svc.cluster.local
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 18044
;; flags: qr aa rd; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
;; WARNING: recursion requested but not available

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
;; QUESTION SECTION:
;web.linkerd-viz.svc.cluster.local. IN	A

;; ANSWER SECTION:
web.linkerd-viz.svc.cluster.local. 30 IN A	198.18.0.245

;; Query time: 1 msec
;; SERVER: 198.18.0.10#53(198.18.0.10)
;; WHEN: Tue Jan 02 16:39:12 UTC 2024
;; MSG SIZE  rcvd: 111
```

# Naming Convention
In Kubernetes, DNS names are assigned to Pods and Services for communication by name instead of IP address. The default domain name used for DNS resolution within the cluster is `cluster.local` and it **SHOULD** be changed when you bootstrap your cluster.

- The DNS name for a Service has the following format: <service-name>.<namespace>.svc.cluster.local
- The DNS name for a Pod has the following format: <pod-ip-address-replace-dot-with-hyphen>.<namespace>.pod.cluster.local.

Here's my naming convention to map internal DNS names to external DNS names:

Outside Kubernetes Cluster:
```
<service name>.<namespace>.<Kubernetes Cluster>.<dnsDomain>
web.linkerd-viz.k8s1-prod.kloud.lan
```

Inside  Kubernetes Cluster:
```
<service name>.<namespace>.<object type>.<dnsDomain>
web.linkerd-viz.svc.cluster.local
```

All the following commands have been executed on a Kubernetes node. I left the prompt for clarity.
```sh
daniel@k8s1master3 ~ $ kubectl get svc -n linkerd-viz web
NAME   TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
web    LoadBalancer   198.18.0.245   198.19.0.5    8084/TCP,9994/TCP   4d9h

# Executed inside a Pod in the Kubernetes Cluster
daniel@k8s1master3 ~ $ kubectl exec -it dnsutils -n dnsutils -- dig +short web.linkerd-viz.svc.cluster.local
198.18.0.245

# Executed outside the Kubernetes Cluster
daniel@k8s1master3 ~ $ dig +short web.linkerd-viz.k8s1-prod.kloud.lan
198.19.0.5

# Executed outside the Kubernetes Cluster
daniel@k8s1master3 ~ $ dig +short web.linkerd-viz.svc.cluster.local
[empty]
```

All the following commands have been from a macOS outside Kubernetes on a separate LAN but with the same DNS server as my Kuberntes nodes. I left the prompt for clarity.
```sh
# Executed outside the Kubernetes Cluster
daniel@MacBook-Dan Downloads % dig +short web.linkerd-viz.k8s1-prod.kloud.lan
198.19.0.5

# Executed outside the Kubernetes Cluster
daniel@MacBook-Dan Downloads % dig +short web.linkerd-viz.svc.cluster.local
[empty]
```

If I'm in a Pod, I use the name below to access the service `web` in namespace `linkerd-viz`
```
web.linkerd-viz.svc.cluster.local       <---> 198.18.0.245
```

If I'm outside the Kubernetes Cluster, I use the name below to access the service `web` in namespace `linkerd-viz` in cluster `cluster.local`
```
web.linkerd-viz.k8s1-prod.kloud.lan   <---> 198.19.0.5
```

# tshark
In case you want to capture packet on your DNS server, here's a `tshark` example. Adjust to your needs:
```sh
tshark -i eth0 -f "host 192.168.13.91 and (udp port 53)" -VV -w dns.pcap

# for CloudFlare with DoT
tshark -i eth0 -f "(host 1.1.1.1 or host 1.0.0.1) and (tcp port 853)" -VV -w dns.pcap
```

# References
[Kubernetes Source IP (SNAT)](https://kubernetes.io/docs/tutorials/services/source-ip/)  
[Delegate a Sub-domain](https://www.zytrax.com/books/dns/ch9/delegate.html)  
[CoreDNS on Kubernetes: Allow DNS zone transfer](https://pet2cattle.com/2022/04/coredns-transfer-dns-zone)  
[Kubernetes Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)  
[Kubernetes DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)  
[CoreDNS k8s_external](https://coredns.io/plugins/k8s_external/)  
[CoreDNS transfer](https://coredns.io/plugins/transfer/)  
[Cilium LoadBalancer IP Address Management](https://docs.cilium.io/en/stable/network/lb-ipam/)
