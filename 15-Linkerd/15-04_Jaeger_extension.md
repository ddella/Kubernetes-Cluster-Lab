# Install the Linkerd-Jaeger extension
The first step of getting distributed tracing setup is installing the Linkerd-Jaeger extension onto your cluster. This extension consists of a collector, a Jaeger backend, and a Jaeger-injector. The collector consumes spans emitted from the mesh and your applications and sends them to the Jaeger backend which stores them and serves a dashboard to view them. The Jaeger-injector is responsible for configuring the Linkerd proxies to emit spans.

To install the Linkerd-Jaeger extension, run the command:
```sh
linkerd jaeger install | kubectl apply -f -
```

You can verify that the Linkerd-Jaeger extension was installed correctly by running:
```sh
linkerd jaeger check
```

> [!NOTE]  
> Install Jaeger extension into a non-default namespace with the command: `linkerd jaeger install --namespace custom | kubectl apply -f -`

The output should be:
```
linkerd-jaeger
--------------
√ linkerd-jaeger extension Namespace exists
√ jaeger extension pods are injected
√ jaeger injector pods are running
√ jaeger extension proxies are healthy
√ jaeger extension proxies are up-to-date
√ jaeger extension proxies and cli versions match

Status check results are √
```

Take a look at everything that was created in the namespace `linkerd-jaeger` with the command:
```sh
kubectl get all -n linkerd-jaeger
```

Output:
```
NAME                                   READY   STATUS    RESTARTS   AGE
pod/collector-5954d7556d-tpxvv         2/2     Running   0          20s
pod/jaeger-595975bfcd-vmmf6            2/2     Running   0          19s
pod/jaeger-injector-7d66674444-d5b4p   2/2     Running   0          20s

NAME                      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                                                    AGE
service/collector         ClusterIP   198.18.1.115   <none>        4317/TCP,4318/TCP,55678/TCP,9411/TCP,14268/TCP,14250/TCP   20s
service/jaeger            ClusterIP   198.18.0.162   <none>        14268/TCP,14250/TCP,16686/TCP                              20s
service/jaeger-injector   ClusterIP   198.18.0.65    <none>        443/TCP                                                    20s

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/collector         1/1     1            1           20s
deployment.apps/jaeger            1/1     1            1           20s
deployment.apps/jaeger-injector   1/1     1            1           20s

NAME                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/collector-5954d7556d         1         1         1       20s
replicaset.apps/jaeger-595975bfcd            1         1         1       20s
replicaset.apps/jaeger-injector-7d66674444   1         1         1       20s
```

## Modify the application

Unlike most features of a service mesh, distributed tracing requires modifying the source of your application. Tracing needs some way to tie incoming requests to your application together with outgoing requests to dependent services. To do this, some headers are added to each request that contain a unique ID for the trace. Linkerd uses the b3 propagation format to tie these things together.

We've already modified emojivoto to instrument its requests with this information, this commit shows how this was done. For most programming languages, it simply requires the addition of a client library to take care of this. Emojivoto uses the OpenCensus client, but others can be used.

To enable tracing in emojivoto, run:
```sh
kubectl -n emojivoto set env --all deploy OC_AGENT_HOST=collector.linkerd-jaeger:55678
```

This command will add an environment variable that enables the applications to propagate context and emit spans.

## Explore Jaeger
With vote-bot starting traces for every request, spans should now be showing up in Jaeger. To get to the UI, run:

Check the new services for Jaeger with the command:
```sh
kubectl get svc -n linkerd-jaeger
```

Output:
```
NAME              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                                                    AGE
collector         ClusterIP   198.18.1.115   <none>        4317/TCP,4318/TCP,55678/TCP,9411/TCP,14268/TCP,14250/TCP   6m25s
jaeger            ClusterIP   198.18.0.162   <none>        14268/TCP,14250/TCP,16686/TCP                              6m25s
jaeger-injector   ClusterIP   198.18.0.65    <none>        443/TCP                                                    6m25s
```

The service that needs to be exposed externally is `jaeger`, the second one. Lets make this service a `Load-Balancer` with an `EXTERNAL-IP`.

### Create IP Pool
Below is a manifest to create an IP Pools, with IPv4 only for the service `jaeger`m and a selector based on the NameSpace named `linkerd-jaeger`. This is where the Jaefer web Pod is located:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "linkerd-jaeger-pool"
spec:
  cidrs:
  - cidr: "198.19.0.56/29"
  serviceSelector:
    matchLabels:
      io.kubernetes.service.namespace: linkerd-jaeger
EOF
```

```
ciliumloadbalancerippool.cilium.io/linkerd-jaeger-pool created
```

After adding the pool to the cluster, it appears like so:
```sh
kubectl get ippools
```

Output:
```
NAME                     DISABLED   CONFLICTING   IPS AVAILABLE   AGE
linkerd-jaeger-pool      false      False         6               15s
```

## Emojivoto Service
I prefer to add an external IP address to the services that I need to access via a browser. This way I can use my laptop. Let's convert the `web-svc` from a type `ClusterIP` to a type `LoadBalancer`.

- change `type: ClusterIP` to `type: LoadBalancer`
- add `allocateLoadBalancerNodePorts: false` under `type: LoadBalancer`

> [!WARNING]  
> If you do the "patching" with 2 commands, you will end up with `targetPort` being allocated. You **NEED** to use a *one-liner*.

```sh
kubectl patch services -n linkerd-jaeger jaeger --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"},{"op":"add","path":"/spec/allocateLoadBalancerNodePorts","value":false}]'
```

Output:
```
service/jaeger patched
```

```sh
kubectl get services -n linkerd-jaeger
```

We know have an external IP, `198.19.0.59`, to access the service from outside the cluster. The port for the `ui` is :
```
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                                                    AGE
collector         ClusterIP      198.18.1.115   <none>        4317/TCP,4318/TCP,55678/TCP,9411/TCP,14268/TCP,14250/TCP   18m
jaeger            LoadBalancer   198.18.0.162   198.19.0.59   14268/TCP,14250/TCP,16686/TCP                              18m
jaeger-injector   ClusterIP      198.18.0.65    <none>        443/TCP                                                    18m
```

> [!NOTE]  
> To find the `TCP/Port`, I checked the service with the command `kubectl get services -n linkerd-jaeger jaeger -o yaml` and saw `name: ui port: 16686`

## Check the UI
Open your browser at `http://198.19.0.59:16686/` or `http://jaeger.linkerd-jaeger.k8s1-prod.kloud.lan:16686` and of course you'll get this message 😉
```
Access to 198.19.0.59 was deniedYou don't have authorization to view this page.
HTTP ERROR 403
```

You can check with the command:
```sh
curl --dump-header - http://jaeger.linkerd-jaeger.k8s1-prod.kloud.lan:16686
```

```
HTTP/1.1 403 Forbidden
content-length: 0
date: Thu, 11 Jan 2024 18:54:42 GMT
```

Check the logs with the command `kubectl logs -n linkerd-jaeger jaeger-595975bfcd-vmmf6 -f`:
```
[  3002.281434s]  INFO ThreadId(01) inbound:server{port=16686}: linkerd_app_inbound::policy::http: Request denied server.group=policy.linkerd.io server.kind=server server.name=jaeger-ui route.group= route.kind=default route.name=default client.tls=None(NoClientHello) client.ip=100.64.11.50
[  3002.281471s]  INFO ThreadId(01) inbound:server{port=16686}:rescue{client.addr=100.64.11.50:53713}: linkerd_app_core::errors::respond: HTTP/1.1 request failed error=client 100.64.11.50:53713: server: 100.64.9.174:16686: unauthorized request on route error.sources=[unauthorized request on route]
[  3005.410085s]  INFO ThreadId(01) inbound:server{port=14269}: linkerd_app_inbound::policy::http: Request denied server.group=policy.linkerd.io server.kind=server server.name=jaeger-admin route.group= route.kind=default route.name=default client.tls=None(NoClientHello) client.ip=100.64.10.116
[  3005.410128s]  INFO ThreadId(01) inbound:server{port=14269}:rescue{client.addr=100.64.10.116:42336}: linkerd_app_core::errors::respond: HTTP/1.1 request failed error=client 100.64.10.116:42336: server: 100.64.9.174:14269: unauthorized request on route error.sources=[unauthorized request on route]
```

# Uninstall
In case you want to uninstall the Linkerd-jaeger extension, use the command:
```sh
linkerd jaeger uninstall | kubectl delete -f -
```
