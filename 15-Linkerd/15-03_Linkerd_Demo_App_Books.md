# Linkerd Demo App
Congratulations, Linkerd and Linkerd Viz are installed! However, it's not doing anything just yet. To see Linkerd in action, we're going to need an application. Let's install a demo application called Emojivoto. Emojivoto is a simple standalone Kubernetes application that uses a mix of gRPC and HTTP calls to allow the user to vote on their favorite emojis.

# Install
Install Emojivoto into the emojivoto namespace by running:
```sh
kubectl create ns booksapp
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/booksapp.yml | kubectl -n booksapp apply -f -
```

Output:
```
service/webapp created
serviceaccount/webapp created
deployment.apps/webapp created
service/authors created
serviceaccount/authors created
deployment.apps/authors created
service/books created
serviceaccount/books created
deployment.apps/books created
serviceaccount/traffic created
deployment.apps/traffic created
```

This command installs BookApp onto your cluster, but Linkerd hasn't been activated on it yet. We'll need to *mesh* the application before Linkerd can work its magic. Before we mesh it, let's take a look at Emojivoto in its natural state. We'll do this by forwarding traffic to its `webapp` service so that we can point our browser to it.

# Modify the existing service `webapp`
Modify the existing service `webapp`, of type `Cluster-IP`, to a service of type `LoadBalancer`.

## Create IP Pool
Below is a manifest to create an IP Pools with IPv4 only and a selector based on the NameSpace named `emojivoto`. This is where the Linkerd web Pod is located:
```sh
cat <<EOF > bookapp-ippool.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "bookapp-pool"
spec:
  cidrs:
  - cidr: "198.19.0.16/29"
  serviceSelector:
    matchLabels:
      io.kubernetes.service.namespace: booksapp
EOF
kubectl apply -f bookapp-ippool.yaml
```

```
ciliumloadbalancerippool.cilium.io/bookapp-pool created
```

After adding the pool to the cluster, it appears like so:
```sh
kubectl get ippools
```

Output:
```
NAME               DISABLED   CONFLICTING   IPS AVAILABLE   AGE
bookapp-pool       false      False         6               20s
```

## Booksapp Service
I prefer to add an external IP address to the services that I need to access via a brower. This way I can use my laptop. Let's convert the `webapp` from a type `ClusterIP` to a type `LoadBalancer`.

Edit the Kubernetes service `webapp` with the command:
```sh
kubectl edit services -n booksapp webapp
```

- change `type: ClusterIP` to `type: LoadBalancer`
- add `allocateLoadBalancerNodePorts: false` under `type: LoadBalancer`

Before the modification:
```
[...]
  selector:
    app: webapp
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```

After the modification:
```
[...]
  selector:
    app: webapp
  sessionAffinity: None
  type: LoadBalancer
  allocateLoadBalancerNodePorts: false
status:
  loadBalancer: {}
```

```sh
kubectl get services -n booksapp webapp
```

We know have an external IP, `198.19.0.21`, to access the service from outside the cluster:
```
NAME     TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
webapp   LoadBalancer   198.18.1.68   198.19.0.21   7000/TCP   5m20s
```

Now visit http://198.19.0.21:7000. Voila! You should see Emojivoto in all its glory. If you click around Emojivoto, you might notice that it's a little broken! For example, if you try to vote for the donut emoji, you'll get a 404 page. Don't worry, these errors are intentional. (In a later guide, we'll show you how to use Linkerd to identify the problem.)

![Emojivoto](./images/booksapp-dashboard.jpg)

## Mesh Booksapp with Linkerd
With Emoji installed and running, we're ready to mesh it. We mean to add Linkerd's data plane proxies to it. We can do this on a live application without downtime, thanks to Kubernetes's rolling deploys. Mesh your Emojivoto application by running:
```sh
kubectl get -n booksapp deploy -o yaml | linkerd inject - | kubectl apply -f -
```

Output:
```
deployment "authors" injected
deployment "books" injected
deployment "traffic" injected
deployment "webapp" injected

deployment.apps/authors configured
deployment.apps/books configured
deployment.apps/traffic configured
deployment.apps/webapp configured
```

Let's take a minute to understand the command above. It
- retrieves all of the deployments running in the emojivoto namespace
- runs their manifests through `linkerd inject`
- then reapplies it to the cluster with `kubectl apply -f -`

The linkerd inject command simply adds annotations to the pod spec that instruct Linkerd to inject the proxy into the pods when they are created.

## Test
Congratulations! 🥳 You've now added Linkerd to an application! Just as with the control plane, it's possible to verify that everything is working the way it should on the data plane side. Check your data plane with:

![Dashboard](./images/booksapp-dashboard-viz.jpg)

```sh
linkerd -n booksapp check --proxy
```

# References
https://linkerd.io/2.14/tasks/books/
