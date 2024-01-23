# Linkerd Viz Dashboard
In this lab, I'm using Cilium CNI with BGP to advertise `EXTERNAL-IP`. I will install a Kubernetes Load Balancer in front of the Linkerd Viz web server. I will map an external IP to the service. There's two ways of doing it. Choose **ONE** not both 😉

- Create a new service of type `LoadBalancer` with an `CiliumLoadBalancerIPPool`
- Modify the existing service of type `Cluster-IP` to a service of type `LoadBalancer`

`CiliumLoadBalancerIPPool` has the notion of IP Pools which the administrator can create to tell Cilium the IP range from which to allocate `EXTERNAL-IP` IPs from.

Below is a manifest to create an IP Pools with IPv4 only and a selector based on the NameSpace named `linkerd-viz`. This is where the Linkerd web Pod is located:
```sh
cat <<EOF > linkerd-viz-ippool.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "linkerd-viz-pool"
spec:
  cidrs:
  - cidr: "198.19.0.0/29"
  serviceSelector:
    matchLabels:
      io.kubernetes.service.namespace: linkerd-viz
EOF
kubectl apply -f linkerd-viz-ippool.yaml
```

```
ciliumloadbalancerippool.cilium.io/linkerd-viz-pool created
```

After adding the pool to the cluster, it appears like so:
```sh
kubectl get ippools
```

Output:
```
NAME               DISABLED   CONFLICTING   IPS AVAILABLE   AGE
linkerd-viz-pool   false      False         5               12s
```

# Services
Any service with `.spec.type=LoadBalancer` can get IPs from any pool as long as the IP Pool's service selector matches the service. If you omit the key/value `type: LoadBalancer` when you create the K8s service, Cilium won't allocate the `EXTERNAL-IP`.

## Modify the existing service of type `Cluster-IP` to a service of type `LoadBalancer`
You could just edit the service and change the following:

- change `type: ClusterIP` to `type: LoadBalancer`
- add `allocateLoadBalancerNodePorts: false` under `spec:`

You can use the command `kubectl edit services -n linkerd-viz web` and modify the service with `vi` editor or just paste the following 2 lines and the services will be updated:

> [!WARNING]  
> If you do the "patching" with 2 commands, you will end up with `targetPort` being allocated. You **NEED** to use a *one-liner*.

```sh
# WILL ALLOCATE "targetPort"
# kubectl patch services -n linkerd-viz web --type merge -p '{"spec":{"type": "LoadBalancer"}}'
# kubectl patch services -n linkerd-viz web --type merge -p '{"spec":{"allocateLoadBalancerNodePorts": false}}'

kubectl patch services -n linkerd-viz web --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"},{"op":"add","path":"/spec/allocateLoadBalancerNodePorts","value":false}]'
```

Output:
```
service/web patched
```

Verify that the service has an `EXTERNAL-IP` and that no `nodePort` have been assigned:
```sh
kubectl get services web -n linkerd-viz
```

Output:
```
NAME   TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
web    LoadBalancer   198.18.1.122   198.19.0.5    8084/TCP,9994/TCP   11m
```

### Service Info
Check the external IP of the service created above.
```sh
kubectl get svc -n linkerd-viz
```

Output for Step B:
```
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
metrics-api       ClusterIP      198.18.0.72    <none>        8085/TCP            44m
prometheus        ClusterIP      198.18.1.131   <none>        9090/TCP            44m
tap               ClusterIP      198.18.1.139   <none>        8088/TCP,443/TCP    44m
tap-injector      ClusterIP      198.18.0.41    <none>        443/TCP             44m
web               LoadBalancer   198.18.1.122   198.19.0.5    8084/TCP,9994/TCP   11m
```

The `EXTERNAL-IP` has been taken from the `linkerd-viz-pool` with CIDR `198.19.0.0/29`.
```sh
kubectl get CiliumLoadBalancerIPPool linkerd-viz-pool -o go-template='External CIDR: {{range .spec.cidrs}}{{.cidr}}{{"\n"}}{{- end -}}'
```

Output:
```
External CIDR: 198.19.0.0/29
```

# Test
We should now be able to access the Linkerd Viz dashboard from any browser. Just point it to `http://198.19.0.5`. Let's try with `curl`:

```sh
curl http://198.19.0.5:8084/
```

Output from the command above:
```
It appears that you are trying to reach this service with a host of '198.19.0.5:8084'.
This does not match /^(localhost|127\.0\.0\.1|web\.linkerd-viz\.svc\.cluster\.local|web\.linkerd-viz\.svc|\[::1\])(:\d+)?$/ and has been denied for security reasons.
Please see https://linkerd.io/dns-rebinding for an explanation of what is happening and how to fix it.
```

We can reach the Pod but we can't access the web page because of **DNS-rebinding protection** that is active by default. See this [page](https://linkerd.io/2.14/tasks/exposing-dashboard/#dns-rebinding-protection)  


This will simulate a connection to `http://web.linkerd-viz.svc:8084` via curl. This time it should work, if the problem above was really **DNS-rebinding protection**.
```sh
curl --resolve web.linkerd-viz.svc:8084:198.19.0.5 http://web.linkerd-viz.svc:8084
```

It does work 😀
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Linkerd</title>
    <meta name="description" content="Linkerd">
    <meta name="keywords" content="Linkerd">
    <link rel="icon" type="image/png" href="/dist/img/favicon.png">
    <link href="https://fonts.googleapis.com/css?family=Lato:300,400,700,900" rel="stylesheet">
    
    <script id="bundle" type="text/javascript" src="/dist/index_bundle.js" async></script>

  </head>
  <body>
    
  <div class="main" id="main"
    data-release-version="stable-2.14.7"
    data-controller-namespace="linkerd"
    data-uuid="70141993-ede8-448a-993b-72be3bcb101d"
    data-grafana=""
    data-grafana-external-url=""
    data-grafana-prefix=""
    data-jaeger="">
    
  </div>

  </body>
</html>
```

## Solution
As a temporary solution, you can change the validation regexp that the dashboard server uses, which is fed into the web deployment via the `enforced-host` container argument. Get the full install `yaml` manifest with the command:
```sh
linkerd viz install > linkerd-viz-install.yaml
```

If you want to completely disable the Host header check, simply use a catch-all regexp `.*` for `-enforced-host`. I'm using this *oneliner* to change the regex. You can use any editor, the argument is at line 1303 for version 2.14.7.
```sh
sed -i 's/\(.*enforced-host=\).*/\1.*/' linkerd-viz-install.yaml
```

The original line looked like this one:
```
        - -enforced-host=^(localhost|127\.0\.0\.1|web\.linkerd-viz\.svc\.cluster\.local|web\.linkerd-viz\.svc|\[::1\])(:\d+)?$
```

The modified line looks like this:
```
        - -enforced-host=.*
```


To install the viz extension fix, run:
```sh
kubectl apply -f linkerd-viz-install.yaml
```

## Verification
Let's do another test with `curl`:
```sh
curl http://198.19.0.5:8084/
```

Problem is fixed 😀:
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Linkerd</title>
    <meta name="description" content="Linkerd">
    <meta name="keywords" content="Linkerd">
    <link rel="icon" type="image/png" href="/dist/img/favicon.png">
    <link href="https://fonts.googleapis.com/css?family=Lato:300,400,700,900" rel="stylesheet">
    
    <script id="bundle" type="text/javascript" src="/dist/index_bundle.js" async></script>
  
  </head>
  <body>
    
  <div class="main" id="main"
    data-release-version="stable-2.14.7"
    data-controller-namespace="linkerd"
    data-uuid="70141993-ede8-448a-993b-72be3bcb101d"
    data-grafana=""
    data-grafana-external-url=""
    data-grafana-prefix=""
    data-jaeger="">
    
  </div>

  </body>
</html>
```

Let's try with a browser.

![Linkerd Viz Dashboard](./images/linkerd-viz-dashboard.jpg)

I'm using BGP for my Kubernetes Cluster and I'm advertising the every `EXTERNAL-IP` to my network. It gives me the ability to use any client to access any Kubernetes services that has an `EXTERNAL-IP`.

## PING
```sh
curl http://198.19.0.5:9994/ping
```

Output:
```
pong
```

## Ready
```sh
curl http://198.19.0.5:9994/ready
```

Output:
```
ok
```

#
```sh
linkerd viz allow-scrapes --namespace emojivoto | kubectl apply -f -
```

Output:
```
server.policy.linkerd.io/proxy-admin created
httproute.policy.linkerd.io/proxy-metrics created
httproute.policy.linkerd.io/proxy-probes created
authorizationpolicy.policy.linkerd.io/prometheus-scrape created
authorizationpolicy.policy.linkerd.io/proxy-probes created
```
