# Linkerd Demo App
Congratulations, Linkerd and Linkerd Viz are installed! However, it's not doing anything just yet. To see Linkerd in action, we're going to need an application. Let's install a demo application called Emojivoto. Emojivoto is a simple standalone Kubernetes application that uses a mix of gRPC and HTTP calls to allow the user to vote on their favorite emojis.

# Install
Install Emojivoto into the emojivoto namespace by running:
```sh
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
```

Output:
```
namespace/emojivoto created
serviceaccount/emoji created
serviceaccount/voting created
serviceaccount/web created
service/emoji-svc created
service/voting-svc created
service/web-svc created
deployment.apps/emoji created
deployment.apps/vote-bot created
deployment.apps/voting created
deployment.apps/web created
```

This command installs Emojivoto onto your cluster, but Linkerd hasn't been activated on it yet. We'll need to *mesh* the application before Linkerd can work its magic. Before we mesh it, let's take a look at Emojivoto in its natural state. We'll do this by forwarding traffic to its `web-svc` service so that we can point our browser to it.

# Modify the existing service `web-svc`
Modify the existing service `web-svc`, of type `Cluster-IP`, to a service of type `LoadBalancer`.

## Create IP Pool
Below is a manifest to create an IP Pools with IPv4 only and a selector based on the NameSpace named `emojivoto`. This is where the Linkerd web Pod is located:
```sh
cat <<EOF > emojivoto-ippool.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "emojivoto-pool"
spec:
  cidrs:
  - cidr: "198.19.0.8/29"
  serviceSelector:
    matchLabels:
      io.kubernetes.service.namespace: emojivoto
EOF
kubectl apply -f emojivoto-ippool.yaml
```

```
ciliumloadbalancerippool.cilium.io/emojivoto-pool created
```

After adding the pool to the cluster, it appears like so:
```sh
kubectl get ippools
```

Output:
```
NAME               DISABLED   CONFLICTING   IPS AVAILABLE   AGE
emojivoto-pool     false      False         6               13s
linkerd-viz-pool   false      False         4               3h56m
```

## Emojivoto Service
I prefer to add an external IP address to the services that I need to access via a browser. This way I can use my laptop. Let's convert the `web-svc` from a type `ClusterIP` to a type `LoadBalancer`.

Edit the Kubernetes service `web-svc` with the command:
```sh
kubectl edit services -n emojivoto web-svc
```

- change `type: ClusterIP` to `type: LoadBalancer`
- add `allocateLoadBalancerNodePorts: false` under `type: LoadBalancer`

Before the modification:
```
[...]
  selector:
    app: web-svc
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```

After the modification:
```
[...]
  selector:
    app: web-svc
  sessionAffinity: None
  type: LoadBalancer
  allocateLoadBalancerNodePorts: false
status:
  loadBalancer: {}
```

```sh
kubectl get services -n emojivoto
```

We know have an external IP, `198.19.0.9`, to access the service from outside the cluster:
```
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
emoji-svc    ClusterIP      198.18.0.255   <none>        8080/TCP,8801/TCP   15m
voting-svc   ClusterIP      198.18.0.176   <none>        8080/TCP,8801/TCP   15m
web-svc      LoadBalancer   198.18.1.223   198.19.0.9    80/TCP              15m
```

Now visit http://198.19.0.9. Voila! You should see Emojivoto in all its glory. If you click around Emojivoto, you might notice that it's a little broken! For example, if you try to vote for the donut emoji, you'll get a 404 page. Don't worry, these errors are intentional. (In a later guide, we'll show you how to use Linkerd to identify the problem.)

![Emojivoto](./images/emoji-web-svc.jpg)

## Mesh Emojivoto with Linkerd
With Emoji installed and running, we're ready to mesh it. We mean to add Linkerd's data plane proxies to it. We can do this on a live application without downtime, thanks to Kubernetes's rolling deploys. Mesh your Emojivoto application by running:
```sh
kubectl get -n emojivoto deploy -o yaml | linkerd inject - | kubectl apply -f -
```

or annotate the namespace. This annotation is all we need to inform Linkerd to inject the proxies into pods in this namespace. However, simply adding the annotation won't affect existing resources. We'll also need to restart the Emojivoto deployments.
```sh
kubectl annotate ns emojivoto linkerd.io/inject=enabled
kubectl rollout restart deploy -n emojivoto
```

Output:
```
deployment "emoji" injected
deployment "vote-bot" injected
deployment "voting" injected
deployment "web" injected

deployment.apps/emoji configured
deployment.apps/vote-bot configured
deployment.apps/voting configured
deployment.apps/web configured
```

Let's take a minute to understand the command above. It
- retrieves all of the deployments running in the emojivoto namespace
- runs their manifests through `linkerd inject`
- then reapplies it to the cluster with `kubectl apply -f -`

The linkerd inject command simply adds annotations to the pod spec that instruct Linkerd to inject the proxy into the pods when they are created.

## prometheus is authorized to scrape data plane pods
Generates policy resources authorizing Prometheus to scrape the data plane proxies in a namespace:
```sh
linkerd viz allow-scrapes --namespace emojivoto | kubectl apply -f -
```
Output
```
server.policy.linkerd.io/proxy-admin created
httproute.policy.linkerd.io/proxy-metrics created
httproute.policy.linkerd.io/proxy-probes created
authorizationpolicy.policy.linkerd.io/prometheus-scrape created
authorizationpolicy.policy.linkerd.io/proxy-probes created
```

## Test
Congratulations! 🥳 You've now added Linkerd to an application! Just as with the control plane, it's possible to verify that everything is working the way it should on the data plane side. Check your data plane with:

![Dashboard](./images/emojivoto-dashboard.jpg)

```sh
linkerd -n emojivoto check --proxy
```

Output:
```
kubernetes-api
--------------
√ can initialize the client
√ can query the Kubernetes API

kubernetes-version
------------------
√ is running the minimum Kubernetes API version

linkerd-existence
-----------------
√ 'linkerd-config' config map exists
√ heartbeat ServiceAccount exist
√ control plane replica sets are ready
√ no unschedulable pods
√ control plane pods are ready
√ cluster networks contains all node podCIDRs
√ cluster networks contains all pods
√ cluster networks contains all services

linkerd-config
--------------
√ control plane Namespace exists
√ control plane ClusterRoles exist
√ control plane ClusterRoleBindings exist
√ control plane ServiceAccounts exist
√ control plane CustomResourceDefinitions exist
√ control plane MutatingWebhookConfigurations exist
√ control plane ValidatingWebhookConfigurations exist
√ proxy-init container runs as root user if docker container runtime is used

linkerd-identity
----------------
√ certificate config is valid
√ trust anchors are using supported crypto algorithm
√ trust anchors are within their validity period
√ trust anchors are valid for at least 60 days
√ issuer cert is using supported crypto algorithm
√ issuer cert is within its validity period
√ issuer cert is valid for at least 60 days
√ issuer cert is issued by the trust anchor

linkerd-webhooks-and-apisvc-tls
-------------------------------
√ proxy-injector webhook has valid cert
√ proxy-injector cert is valid for at least 60 days
√ sp-validator webhook has valid cert
√ sp-validator cert is valid for at least 60 days
√ policy-validator webhook has valid cert
√ policy-validator cert is valid for at least 60 days

linkerd-identity-data-plane
---------------------------
√ data plane proxies certificate match CA

linkerd-version
---------------
√ can determine the latest version
√ cli is up-to-date

linkerd-control-plane-proxy
---------------------------
√ control plane proxies are healthy
√ control plane proxies are up-to-date
√ control plane proxies and cli versions match

linkerd-data-plane
------------------
√ data plane namespace exists
√ data plane proxies are ready
√ data plane is up-to-date
√ data plane and cli versions match
√ data plane pod labels are configured correctly
√ data plane service labels are configured correctly
√ data plane service annotations are configured correctly
√ opaque ports are properly annotated

linkerd-ha-checks
-----------------
√ pod injection disabled on kube-system
√ multiple replicas of control plane pods

linkerd-viz
-----------
√ linkerd-viz Namespace exists
√ can initialize the client
√ linkerd-viz ClusterRoles exist
√ linkerd-viz ClusterRoleBindings exist
√ tap API server has valid cert
√ tap API server cert is valid for at least 60 days
√ tap API service is running
√ linkerd-viz pods are injected
√ viz extension pods are running
√ viz extension proxies are healthy
√ viz extension proxies are up-to-date
√ viz extension proxies and cli versions match
√ prometheus is installed and configured correctly
√ viz extension self-check

linkerd-viz-data-plane
----------------------
√ data plane namespace exists
√ prometheus is authorized to scrape data plane pods
√ data plane proxy metrics are present in Prometheus

Status check results are √
```

```sh
linkerd viz top deployment/emoji --namespace emojivoto
linkerd viz top deployment/voting --namespace emojivoto
```

