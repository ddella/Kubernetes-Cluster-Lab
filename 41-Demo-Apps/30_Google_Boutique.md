# Google Boutique

Get the manifest file
```sh
curl -LO https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
```

Deploy Online Boutique to the cluster in namespace `boutique` with the commands:
```sh
kubectl create namespace boutique
kubectl apply -n boutique -f kubernetes-manifests.yaml
```

Output:
```
deployment.apps/emailservice created
service/emailservice created
deployment.apps/checkoutservice created
service/checkoutservice created
deployment.apps/recommendationservice created
service/recommendationservice created
deployment.apps/frontend created
service/frontend created
service/frontend-external created
deployment.apps/paymentservice created
service/paymentservice created
deployment.apps/productcatalogservice created
service/productcatalogservice created
deployment.apps/cartservice created
service/cartservice created
deployment.apps/loadgenerator created
deployment.apps/currencyservice created
service/currencyservice created
deployment.apps/shippingservice created
service/shippingservice created
deployment.apps/redis-cart created
service/redis-cart created
deployment.apps/adservice created
service/adservice created
```

Wait for the pods to be ready.
```sh
kubectl get pods -n boutique
```

# Service
The service that will be exposed externally is `frontend-external`. Let's make sure it gets an `EXTERNAL-IP`. For now the status is `<pending>` and that's expected. It 
```sh
kubectl get services -n boutique frontend-external
```

Output:
```
NAME                TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
frontend-external   LoadBalancer   198.18.0.248   <pending>     80:31329/TCP   86s
```

## frontend-external service
In this lab, I'm using Cilium CNI with BGP to advertise `EXTERNAL-IP`. I will install a Kubernetes Load Balancer in front of the metric server. I will map an external IP to the service.

- Create a new service of type `LoadBalancer` with an `CiliumLoadBalancerIPPool`
- Modify the existing service of type `Cluster-IP` to a service of type `LoadBalancer`

`CiliumLoadBalancerIPPool` has the notion of IP Pools which the administrator can create to tell Cilium the IP range from which to allocate `EXTERNAL-IP` IPs from.

Below is a manifest to create an IP Pools with IPv4 only and a selector based on the NameSpace named `boutique`. This is where the `frontend-external` Pod is located:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "boutique-pool"
spec:
  cidrs:
  - cidr: "198.19.0.48/29"
  serviceSelector:
    matchLabels:
      io.kubernetes.service.namespace: boutique
EOF
```

```
ciliumloadbalancerippool.cilium.io/boutique-pool created
```

## Patch the service
You can use the command `kubectl edit services -n boutique frontend-external` and modify the service with `vi` editor or just paste the following lines and the services will be updated:
```sh
kubectl patch services -n boutique frontend-external --type=json -p '[{"op":"replace","path":"/spec/type","value":"ClusterIP"}]'
kubectl patch services -n boutique frontend-external --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"},{"op":"add","path":"/spec/allocateLoadBalancerNodePorts","value":false}]'
```

> [!NOTE]  
> I converted the service from `LoadBalancer` to `ClusterIP` to `LoadBalancer` 😀 The reason I did that is to remove the `nodePort` that I don't need since I'm using BGP to advertise my `EXTERNAL IP`.

Get the IP address with the command:
```sh
kubectl get services -n boutique frontend-external
kubectl get services -n boutique frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
```

Output:
```
NAME                TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
frontend-external   LoadBalancer   198.18.0.248   198.19.0.50   80/TCP         10m
```

Visit http://198.19.0.50/ in a web browser to access your instance of *Online Boutique*.

# Mesh
This demonstrate how to add Linkerd to the Google Boutique Demo

## Mesh Google Boutique Demo with Linkerd
With the Boutique installed and running, we're ready to mesh it. We mean to add Linkerd's data plane proxies to it. We can do this on a live application without downtime, thanks to Kubernetes's rolling deploys.

Use the command below to mesh your Boutique application with Linkerd:
```sh
kubectl get -n boutique deploy -o yaml | linkerd inject - | kubectl apply -f -
```

Output:
```
deployment "adservice" injected
deployment "cartservice" injected
deployment "checkoutservice" injected
deployment "currencyservice" injected
deployment "emailservice" injected
deployment "frontend" injected
deployment "loadgenerator" injected
deployment "paymentservice" injected
deployment "productcatalogservice" injected
deployment "recommendationservice" injected
deployment "redis-cart" injected
deployment "shippingservice" injected

deployment.apps/adservice configured
deployment.apps/cartservice configured
deployment.apps/checkoutservice configured
deployment.apps/currencyservice configured
deployment.apps/emailservice configured
deployment.apps/frontend configured
deployment.apps/loadgenerator configured
deployment.apps/paymentservice configured
deployment.apps/productcatalogservice configured
deployment.apps/recommendationservice configured
deployment.apps/redis-cart configured
deployment.apps/shippingservice configured
```

Let's take a minute to understand the command above. It
- retrieves all of the deployments running in the `boutique` namespace
- runs their manifests through `linkerd inject`
- then reapplies it to the cluster with `kubectl apply -f -`

The `linkerd inject` command simply adds annotations to the pod spec that instruct Linkerd to inject the proxy into the pods when they are created.

## Verification

### Linkerd Viz
See the Boutique with Linkerd Viz

![Boutique Hubble UI](./images/boutique-dashboard-viz.jpg)

### Hubble UI
I had Cilium Hubble UI installed. Here's what the Boutique app look like

![Boutique Hubble UI](./images/boutique-hubble-ui.jpg)

Congratulations! 🥳 You've now added Linkerd 🎈 to Google Boutique Demo!

# Unmesh Google Boutique Demo
If you need to unmesh an application, you can do so with the command below:
```sh
kubectl get -n boutique deploy -o yaml | linkerd uninject - | kubectl apply -f -
```

Output:
```
deployment "adservice" uninjected
deployment "cartservice" uninjected
deployment "checkoutservice" uninjected
deployment "currencyservice" uninjected
deployment "emailservice" uninjected
deployment "frontend" uninjected
deployment "loadgenerator" uninjected
deployment "paymentservice" uninjected
deployment "productcatalogservice" uninjected
deployment "recommendationservice" uninjected
deployment "redis-cart" uninjected
deployment "shippingservice" uninjected

deployment.apps/adservice configured
deployment.apps/cartservice configured
deployment.apps/checkoutservice configured
deployment.apps/currencyservice configured
deployment.apps/emailservice configured
deployment.apps/frontend configured
deployment.apps/loadgenerator configured
deployment.apps/paymentservice configured
deployment.apps/productcatalogservice configured
deployment.apps/recommendationservice configured
deployment.apps/redis-cart configured
deployment.apps/shippingservice configured
```

# References
[Google Boutique Demo on GitHub](https://github.com/GoogleCloudPlatform/microservices-demo)  
