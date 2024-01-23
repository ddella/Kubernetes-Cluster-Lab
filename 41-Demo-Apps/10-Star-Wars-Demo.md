# Getting Started with the Star Wars Demo
When we have Cilium deployed and kube-dns operating correctly we can deploy our demo application.

In our Star Wars-inspired example, there are three microservices applications: `deathstar`, `tiefighter`, and `xwing`. The `deathstar` runs an HTTP webservice on port 80, which is exposed as a Kubernetes Service to load-balance requests to `deathstar` across two pod replicas. The `deathstar` service provides landing services to the empire's spaceships so that they can request a landing port. The `tiefighter` pod represents a landing-request client service on a typical empire ship and xwing represents a similar service on an alliance ship. They exist so that we can test different security policies for access control to deathstar landing services.

## Application Topology for Cilium and Kubernetes
The file `http-sw-app.yaml` contains a Kubernetes Deployment for each of the three services. Each deployment is identified using the Kubernetes labels `(org=empire, class=deathstar)`, `(org=empire, class=tiefighter)`, and `(org=alliance, class=xwing)`. It also includes a `deathstar-service`, which load-balances traffic to all pods with label `(org=empire, class=deathstar)`.

Create the demo in the namespace `star-wars`:
```sh
kubectl create ns star-wars
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.14.5/examples/minikube/http-sw-app.yaml -n star-wars
```

Output:
```
namespace/star-wars created

service/deathstar created
deployment.apps/deathstar created
pod/tiefighter created
pod/xwing created
```

### Verify
```sh
kubectl get all -n star-wars
```

Output:
```
NAME                            READY   STATUS    RESTARTS   AGE
pod/deathstar-f449b9b55-5zjjv   1/1     Running   0          101s
pod/deathstar-f449b9b55-sfkgj   1/1     Running   0          101s
pod/tiefighter                  1/1     Running   0          101s
pod/xwing                       1/1     Running   0          101s

NAME                TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/deathstar   ClusterIP   198.18.0.94   <none>        80/TCP    102s

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/deathstar   2/2     2            2           102s

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/deathstar-f449b9b55   2         2         2       102s
```

# Check Current Access
From the perspective of the deathstar service, only the ships with label `org=empire` are allowed to connect and request landing. Since we have no rules enforced, both `xwing` and `tiefighter` will be able to request landing. To test this, use the commands below.
```sh
kubectl exec xwing -n star-wars -- curl -s -XPOST deathstar.star-wars.svc.cluster.local/v1/request-landing
```

```sh
kubectl exec tiefighter -n star-wars -- curl -s -XPOST deathstar.star-wars.svc.cluster.local/v1/request-landing
```

Both commands will output:
```
Ship landed
```

# Clean-up
```sh
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.14.5/examples/minikube/http-sw-app.yaml
kubectl delete ns star-wars
kubectl delete cnp rule1
```

> [!NOTE]  
> Delete the namespace should be sufficient.

# References
[Cilium Star Wars Demo](https://docs.cilium.io/en/stable/gettingstarted/demo/)  
