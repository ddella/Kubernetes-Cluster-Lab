# Load Balancer with Cilium
LB IPAM is a feature that allows Cilium to assign IP addresses to Services of type LoadBalancer. This functionality is usually left up to a cloud provider, however, when deploying in a private cloud environment, these facilities are not always available.

LB IPAM works in conjunction with features like the Cilium BGP Control Plane. Where LB IPAM is responsible for allocation and assigning of IPs to Service objects and other features are responsible for load balancing and/or advertisement of these IPs.

LB IPAM is always enabled but dormant. The controller is awoken when the first IP Pool is added to the cluster.

## Nginx Deployment
This tutorial uses a simple Nginx web server deployment to demonstrate the concept of load balancer and external IP addresses. We will create Pods with two containers each.
- Nginx servicing the `index.html` from a volume
- Alpine updating the `index.html` every 5 seconds

### Create NameSpace
Create a namespace for this demo. It will be our selector to assign external load balancer IP addresses:
```sh
cat <<EOF > nginx-ns.yaml
kind: Namespace
apiVersion: v1
metadata:
  name: nginx
  labels:
    name: nginx
EOF
kubectl create -f nginx-ns.yaml
```

### Create Deployment
This will create six Pods in NameSpace `nginx`:
```sh
cat <<'EOF' > nginx-dp.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-v1
  namespace: nginx
spec:
  replicas: 6
  selector:
    matchLabels:
      app: hello-v1
  template:
    metadata:
      labels:
        app: hello-v1
        frontend: nginx
        backend: alpine
    spec:
      containers:
      - name: nginx-container
        image: nginx
        ports:
        - containerPort: 80
        volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html

      - name: alpine-container
        image: alpine
        command: ['/bin/sh']
        args: ['-c', 'while true; do echo "Hello, Kubernetes $(date) from $(hostname) at $(hostname -i)" > /pod-data/index.html; sleep 5 ; done']
        volumeMounts:
        - name: shared-data
          mountPath: /pod-data

      volumes:
      - name: shared-data
        emptyDir: {}
EOF
kubectl apply -f nginx-dp.yaml
```

> [!IMPORTANT]  
> Don't forget to quote the `'EOF'` above to keep the variables in the script of the alpine container.

### Verify
Check that the Pods are running in namespace `nginx`:
```sh
kubectl get pods -n nginx -l app=hello-v1 -o wide
```

Output:
```
NAME                        READY   STATUS    RESTARTS   AGE     IP             NODE                    NOMINATED NODE   READINESS GATES
hello-v1-69c47b7c78-87q6j   2/2     Running   0          2m24s   100.64.7.173   k8s1worker2.kloud.lan   <none>           <none>
hello-v1-69c47b7c78-99gf6   2/2     Running   0          2m24s   100.64.8.9     k8s1worker3.kloud.lan   <none>           <none>
hello-v1-69c47b7c78-g96h7   2/2     Running   0          2m24s   100.64.11.94   k8s1worker6.kloud.lan   <none>           <none>
hello-v1-69c47b7c78-kz8jg   2/2     Running   0          2m24s   100.64.10.62   k8s1worker5.kloud.lan   <none>           <none>
hello-v1-69c47b7c78-rpkk2   2/2     Running   0          2m24s   100.64.6.223   k8s1worker1.kloud.lan   <none>           <none>
hello-v1-69c47b7c78-v4bn7   2/2     Running   0          2m24s   100.64.9.64    k8s1worker4.kloud.lan   <none>           <none>
```

Another way to get the IP address of the Pods and on what node they are running:
```sh
kubectl get pods -l app=hello-v1 -n nginx -o go-template='{{- range .items -}}K8s Node: {{.spec.nodeName}} --- Pod IP: {{.status.podIP}}{{"\n"}}{{- end -}}'
```

Output:
```
K8s Node: k8s1worker2.kloud.lan --- Pod IP: 100.64.7.173
K8s Node: k8s1worker3.kloud.lan --- Pod IP: 100.64.8.9
K8s Node: k8s1worker6.kloud.lan --- Pod IP: 100.64.11.94
K8s Node: k8s1worker5.kloud.lan --- Pod IP: 100.64.10.62
K8s Node: k8s1worker1.kloud.lan --- Pod IP: 100.64.6.223
K8s Node: k8s1worker4.kloud.lan --- Pod IP: 100.64.9.64
```

## LB IPAM
LB IPAM has the notion of IP Pools which the administrator can create to tell Cilium the IP range from which to allocate IPs from.

Below is a manifest to create an IP Pools with IPv4 only and a selector based on the NameSpace named `nginx`:
```sh
cat <<EOF > nginx-ippool.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "nginx-pool"
spec:
  cidrs:
  - cidr: "198.19.254.0/23"
  serviceSelector:
    matchLabels:
      io.kubernetes.service.namespace: nginx
EOF
kubectl create -f nginx-ippool.yaml
```

```
ciliumloadbalancerippool.cilium.io/nginx-pool created
```

After adding the pool to the cluster, it appears like so:
```sh
kubectl get ippools
```

Output:
```
NAME         DISABLED   CONFLICTING   IPS AVAILABLE   AGE
nginx-pool   false      False         510             15s
```

## Services
Any service with `.spec.type=LoadBalancer` can get IPs from any pool as long as the IP Pool's service selector matches the service. If you omit the key/value `type: LoadBalancer` when you create the K8s service, Cilium won't allocate the External IP.

Create a simple service:
```sh
cat <<EOF > nginx-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-v1-svc
  namespace: nginx
  labels:
    run: my-nginx
spec:
  type: LoadBalancer
  # Don't create NodePort
  allocateLoadBalancerNodePorts: false
  ports:
  - protocol: TCP
    port: 80
  selector:
    # Make sure this matches the label of the Pod
    app: hello-v1
EOF
kubectl apply -f nginx-svc.yaml
```

Output:
```
service/hello-v1-svc created
```

### Service Info
Check the external IP of the service created above.
```sh
kubectl get svc -n nginx
```

Output:
```
NAME           TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)   AGE
hello-v1-svc   LoadBalancer   198.18.1.148   198.19.255.25   80/TCP    2s
```

The EXTERNAL-IP has been taken from the `nginx-pool` with CIDR `198.19.254.0/23`.
```sh
kubectl get CiliumLoadBalancerIPPool nginx-pool -o go-template='External CIDR: {{range .spec.cidrs}}{{.cidr}}{{"\n"}}{{- end -}}'
```

# Test
Let's test our Nginx deployment by pointing a client to the `EXTERNAL-IP` of the load balancer. 

```sh
while true; do curl http://198.19.255.25; sleep 1; done
```

> [!IMPORTANT]  
> If you're on a server that is **not** part of the K8s cluster, it may not have the route even if you're running BGP inside your K8s Cluster. You may need to add a static route to reach the external subnet. An example is a route pointing to any hosts: `sudo ip route add 198.19.254.0/23 via 192.168.13.91`

# Cleanup
Remove everything we created for this demo:

- Nginx service
- IP Pool created for this demo
- Nginx Deployment
- Nginx NameSpace (deleting the namespace would have deleted the deployment)
- Static route

```sh
kubectl delete -f nginx-svc.yaml
kubectl delete -f nginx-ippool.yaml
kubectl delete -f nginx-dp.yaml
kubectl delete -f nginx-ns.yaml
```

> [!NOTE]  
> Removing the ippool and the namespace should be sufficient.

Delete the static route, if you added one:
```sh
sudo ip route delete 198.19.254.0/23
```

# References
[LoadBalancer IP Address Management (LB IPAM)](https://docs.cilium.io/en/stable/network/lb-ipam/)  
