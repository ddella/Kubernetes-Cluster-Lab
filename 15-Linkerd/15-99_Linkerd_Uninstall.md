# Uninstalling Linkerd
Removing Linkerd from a Kubernetes cluster requires a few steps:
1. removing any data plane proxies
2. removing all the extensions
3. then removing the core control plane.

## Step 1: Removing Linkerd data plane proxies
To remove the Linkerd data plane proxies, you should remove any Linkerd proxy injection annotations and roll the deployments. When Kubernetes recreates the pods, they will not have the Linkerd data plane attached.

Those are examples on how to remove the Linkerd data plane proxies. You need to adjust:
```sh
# Uninject all the deployments in the emojivoto namespace.
kubectl get -n emojivoto deploy -o yaml | linkerd uninject - | kubectl apply -f -

# Download a resource and uninject it through stdin.
curl http://url.to/yml | linkerd uninject - | kubectl apply -f -

# Uninject all the resources inside a folder and its sub-folders.
linkerd uninject <folder> | kubectl apply -f -
```

## Step 2: Removing extensions
To remove any extension, call its uninstall subcommand and pipe it to `kubectl delete -f -`.

### Remove Linkerd Viz
```sh
linkerd viz uninstall | kubectl delete -f -
```

### Remove Linkerd Jaeger
```sh
linkerd jaeger uninstall | kubectl delete -f -
```

### Remove Linkerd Multicluster
```sh
linkerd multicluster uninstall | kubectl delete -f -
```

## Step 3: Removing the control plane

> [!NOTE]  
> Uninstallating the control plane requires cluster-wide permissions.

To remove the control plane, run:
```sh
linkerd install --crds | kubectl delete -f -
linkerd uninstall -f | kubectl delete -f -
```

The `linkerd uninstall` command outputs the manifest for all of the Kubernetes resources necessary for the control plane, including namespaces, service accounts, CRDs, and more; `kubectl delete` then deletes those resources.

This command can also be used to remove control planes that have been partially installed. Note that `kubectl delete` will complain about any resources that it was asked to delete that hadn't been created, but these errors can be safely ignored.
