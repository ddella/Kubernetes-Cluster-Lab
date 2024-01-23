# Linkerd

# Linkerd CLI installation

## Custom linkerd CLI Install
I didn't like to have the Linkerd CLI in every local directory on every local machine. We have some bastion hosts, so I deciced to strip down the installation with this *home made* script 😀 When I have the time, I'll rewrite to have all the checks it should have but for now that will do the job.

Check the latest version:
```sh
VER=$(curl -s https://api.github.com/repos/linkerd/linkerd2/releases/latest | grep tag_name | cut -d '"' -f 4|sed 's/v//g')
echo $VER
```

Install the CLI in `/usr/local/bin/` with the commands:
```sh
curl -OL https://github.com/linkerd/linkerd2/releases/download/${VER}/linkerd2-cli-${VER}-linux-amd64
sudo install -g adm -o root linkerd2-cli-${VER}-linux-amd64 /usr/local/bin/linkerd-stable-${VER}
sudo ln -fs /usr/local/bin/linkerd-stable-${VER} /usr/local/bin/linkerd
```

Create the directory `~/.linkerd2`. I don't know yet if it's really required.
```sh
mkdir $HOME/.linkerd2
```

Cleanup the binary downloaded in the step above:
```sh
rm -f linkerd2-cli-${VER}-linux-amd64
unset VER
```

## Verification
Check that linkerd CLI has been installed and is working as expected.
```sh
linkerd version
```

Output:
```
Client version: stable-2.14.7
Server version: unavailable
```

> [!NOTE]  
> The server version is `unavailable` because we haven't deploy linkerd control-plane yet.

# Installing Linkerd with Helm
Linkerd can be installed via Helm rather than with the `linkerd install` command. This is recommended for production, since it allows for repeatability. An example where you would need to install Linkerd with Helm is for Kubernetes clusters that make use of Linkerd's multi-cluster communication. You must share a trust anchor and the default `linkerd install` setup will not work for this situation. You must provide an explicit trust anchor.

## Step 0: Setup
We need to ensure you have access to modern Kubernetes cluster and a functioning `kubectl` command on your local machine. Validate your Kubernetes setup by running:
```sh
kubectl version
```

You should see output with both a Client Version and Server Version component. Now that we have our cluster, we'll install the Linkerd CLI and use it validate that your cluster is capable of hosting Linkerd.

Output:
```
Client Version: v1.28.4
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
Server Version: v1.28.4
```

## Step 1: Install the CLI
Already done

## Step 2: Validate your Kubernetes cluster
Kubernetes clusters can be configured in many different ways. Before we can install the Linkerd control plane, we need to check and validate that everything is configured correctly. To check that your cluster is ready to install Linkerd, run:

```sh
linkerd check --pre
```

Output should look like this with all *green checks*:
```
kubernetes-api
--------------
√ can initialize the client
√ can query the Kubernetes API

kubernetes-version
------------------
√ is running the minimum Kubernetes API version

pre-kubernetes-setup
--------------------
√ control plane namespace does not already exist
√ can create non-namespaced resources
√ can create ServiceAccounts
√ can create Services
√ can create Deployments
√ can create CronJobs
√ can create ConfigMaps
√ can create Secrets
√ can read Secrets
√ can read extension-apiserver-authentication configmap
√ no clock skew detected

linkerd-version
---------------
√ can determine the latest version
√ cli is up-to-date

Status check results are √
```

If there are any checks that do not pass, make sure to follow the provided links and fix those issues before proceeding.

## Step 3: Add Helm install Linkerd repo stable release
If you don't have `helm`, you need to install it. Add the repo for Linkerd stable releases and update it:
```sh
helm repo add linkerd https://helm.linkerd.io/stable
helm repo update
```

## Step 4: Helm install procedure
You need to install two separate charts in succession:
1. linkerd-crds
2. linkerd-control-plane

### Linkerd-crds
The linkerd-crds chart sets up the CRDs linkerd requires:
```sh
helm install linkerd-crds linkerd/linkerd-crds -n linkerd --create-namespace
```

Output:
```
NAME: linkerd-crds
LAST DEPLOYED: Wed Dec 27 20:07:38 2023
NAMESPACE: linkerd
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The linkerd-crds chart was successfully installed 🎉

To complete the linkerd core installation, please now proceed to install the
linkerd-control-plane chart in the linkerd namespace.

Looking for more? Visit https://linkerd.io/2/getting-started/
```

### View the chart values
```sh
# helm show values linkerd/linkerd-control-plane
helm fetch --untar linkerd/linkerd-control-plane
```

### linkerd-control-plane
Modify the file `linkerd-control-plane/values.yaml` and adjust the `clusterNetworks`. In my case, I added the my service CIDR `198.18.0.0/23`:
```
sed -i 's/\(clusterNetworks:\).*/\1 "10.0.0.0\/8,100.64.0.0\/10,172.16.0.0\/12,192.168.0.0\/16,198.18.0.0\/15"/' linkerd-control-plane/values.yaml
```

The linkerd-control-plane chart sets up all the control plane components:
```sh
helm install linkerd-control-plane -n linkerd \
--set-file identityTrustAnchorsPEM=ca-crt.pem \
--set-file identity.issuer.tls.crtPEM=int-crt.pem \
--set-file identity.issuer.tls.keyPEM=int-key.pem \
-f linkerd-control-plane/values.yaml \
-f linkerd-control-plane/values-ha.yaml \
linkerd/linkerd-control-plane
```

Output:
```
NAME: linkerd-control-plane
LAST DEPLOYED: Wed Dec 27 20:15:26 2023
NAMESPACE: linkerd
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Linkerd control plane was successfully installed 🎉

To help you manage your Linkerd service mesh you can install the Linkerd CLI by running:

  curl -sL https://run.linkerd.io/install | sh

Alternatively, you can download the CLI directly via the Linkerd releases page:

  https://github.com/linkerd/linkerd2/releases/

To make sure everything works as expected, run the following:

  linkerd check

The viz extension can be installed by running:

  helm install linkerd-viz linkerd/linkerd-viz

Looking for more? Visit https://linkerd.io/2/getting-started/
```

## Step 5: Verify installation
```sh
linkerd check
```

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

linkerd-version
---------------
√ can determine the latest version
√ cli is up-to-date

control-plane-version
---------------------
√ can retrieve the control plane version
√ control plane is up-to-date
√ control plane and cli versions match

linkerd-control-plane-proxy
---------------------------
√ control plane proxies are healthy
√ control plane proxies are up-to-date
√ control plane proxies and cli versions match

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

Status check results are √
```

> [!WARNING]  
> Near the bottom it says "linkerd-viz Namespace exists" but `linkerd-viz` doesn't exists according to `kubectl get ns`!!!

## Step 6: Install Linkerd VIZ (Optional)

[USE THE FOLLOWING GUIDE](./15-01_Linkerd_Dashboard.md)

### View the chart values
```sh
# helm show values linkerd/linkerd-viz
helm fetch --untar linkerd/linkerd-viz
```

Modify the file `linkerd-viz/values.yaml` and adjust the `linkerd-viz/values.yaml` if you plan to use jaeger extension:
```
sed -i 's/jaegerUrl: ""/jaegerUrl: "jaeger.linkerd-jaeger.svc.cluster.local:16686"/' linkerd-viz/values.yaml
```

Install VIZ extention:
```sh
helm install linkerd-viz linkerd/linkerd-viz -n linkerd-viz --create-namespace \
-f linkerd-viz/values.yaml \
-f linkerd-viz/values-ha.yaml
```

Output:
```
NAME: linkerd-viz
LAST DEPLOYED: Wed Dec 27 20:37:15 2023
NAMESPACE: linkerd-viz
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Linkerd Viz extension was successfully installed 🎉

To make sure everything works as expected, run the following:

  linkerd viz check

To view the linkerd dashboard, run the following:

  linkerd viz dashboard

Looking for more? Visit https://linkerd.io/2/getting-started/
```

Check the installation:
```sh
linkerd viz check
```

Output for a sucessfull check:
```
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

Status check results are √
```

> [!IMPORTANT]  
> I had an issue where the command `linkerd viz check` would failed. I noticed that the `default` namespace was tagged with the label `linkerd.io/extension`. See below
> 
> ```
> kubectl get ns -l linkerd.io/extension
> NAME          STATUS   AGE
> default       Active   54d
> linkerd-viz   Active   14d
> ```
> 
> I just removed the label and everything worked.
> ```
> kubectl label namespace default linkerd.io/extension-
> namespace/default unlabeled
> ```

# Uninstalling Linkerd
Removing Linkerd from a Kubernetes cluster requires a few steps:
1. removing any data plane proxies
2. removing all the extensions
3. removing the core control plane.

## Step 1: Removing Linkerd data plane proxies
To remove the Linkerd data plane proxies, you should remove any Linkerd proxy injection annotations and roll the deployments. When Kubernetes recreates the pods, they will not have the Linkerd data plane attached.

## Step 2: Removing extensions
To remove any extension, call its uninstall subcommand and pipe it to kubectl delete -f -. For the bundled extensions that means:

To remove Linkerd Viz:
```sh
helm uninstall linkerd-viz -n linkerd-viz
```

## Step 3: Removing the control plane

> [!NOTE]  
> Uninstallating the control plane requires cluster-wide permissions.

To remove the control plane, run:
```sh
helm uninstall linkerd-control-plane -n linkerd
helm uninstall linkerd-crds -n linkerd
```

Output from the last three commands:
```
release "linkerd-viz" uninstalled
release "linkerd-control-plane" uninstalled
release "linkerd-crds" uninstalled
```

## Step 4: Remove the namespaces
```sh
kubectl delete namespaces linkerd
kubectl delete namespaces linkerd-viz
```

# References
[Helm](https://artifacthub.io/packages/helm/linkerd2/linkerd-control-plane)  
[Installing Linkerd with Helm](https://linkerd.io/2.14/tasks/install-helm/)  

--------------------------------

# Install via CLI (NOT TESTED)
Now that you have the CLI running locally and a cluster that is ready to go, it's time to install Linkerd on your Kubernetes cluster. To do this, run:

```sh
linkerd install --crds | kubectl apply -f -
linkerd install --set clusterNetworks="198.18.0.0/15\,100.64.0.0/16" | kubectl apply -f -
```

The `install --crds` command installs Linkerd's Custom Resource Definitions (CRDs), which must be installed first, while the `install --set clusterNetworks` command installs the Linkerd control plane.

> [!IMPORTANT]  
> Add the Pods and Services network CIDR to avoid warning like: `the Linkerd clusterNetworks [...] do not include svc default/kubernetes`

# Explore Linkerd!
Let's install Linkerd viz extension, which will install an on-cluster metric stack and dashboard.

To install the viz extension, run:

```sh
linkerd viz install | kubectl apply -f -
```

```sh
linkerd viz dashboard &
```

# Install the demo app
Congratulations, Linkerd is installed! However, it's not doing anything just yet. To see Linkerd in action, we'e going to need an application.

Let's install a demo application called Emojivoto. Emojivoto is a simple standalone Kubernetes application that uses a mix of gRPC and HTTP calls to allow the user to vote on their favorite emojis.

Install Emojivoto into the emojivoto namespace by running:

```sh
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
```

# 
That's it! 👏

Congratulations, you have joined the exalted ranks of Linkerd users! Give yourself a pat on the back.

---

# Upgrade TL;DR

```sh
VER=$(curl -s https://api.github.com/repos/linkerd/linkerd2/releases/latest | grep tag_name | cut -d '"' -f 4|sed 's/v//g')
echo $VER
curl -OL https://github.com/linkerd/linkerd2/releases/download/${VER}/linkerd2-cli-${VER}-linux-amd64
sudo install -g adm -o root linkerd2-cli-${VER}-linux-amd64 /usr/local/bin/linkerd-stable-${VER}
sudo ln -fs /usr/local/bin/linkerd-stable-${VER} /usr/local/bin/linkerd
mkdir $HOME/.linkerd2
rm -f linkerd2-cli-${VER}-linux-amd64
unset VER

helm upgrade linkerd-crds linkerd/linkerd-crds -n linkerd --create-namespace

helm fetch --untar linkerd/linkerd-control-plane
sed -i 's/\(clusterNetworks:\).*/\1 "10.0.0.0\/8,100.64.0.0\/10,172.16.0.0\/12,192.168.0.0\/16,198.18.0.0\/15"/' linkerd-control-plane/values.yaml
daniel@k8s1bastion1 ~/Linkerd $ helm upgrade linkerd-control-plane -n linkerd \
--set-file identityTrustAnchorsPEM=ca-crt.pem \
--set-file identity.issuer.tls.crtPEM=int-crt.pem \
--set-file identity.issuer.tls.keyPEM=int-key.pem \
-f linkerd-control-plane/values.yaml \
-f linkerd-control-plane/values-ha.yaml \
linkerd/linkerd-control-plane

helm fetch --untar linkerd/linkerd-viz
helm upgrade linkerd-viz linkerd/linkerd-viz -n linkerd-viz --create-namespace
linkerd viz install > linkerd-viz-install.yaml
sed -i 's/\(.*enforced-host=\).*/\1.*/' linkerd-viz-install.yaml
kubectl apply -f linkerd-viz-install.yaml
kubectl patch services -n linkerd-viz web --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"},{"op":"add","path":"/spec/allocateLoadBalancerNodePorts","value":false}]'
```

Leave a couple of seconds and you should be able to view the page Linkerd Viz at: `http://web.linkerd-viz.k8s1-prod.kloud.lan:8084/`. If you get the error:
```
This does not match /^(localhost|127\.0\.0\.1|web\.linkerd-viz\.svc\.cluster\.local|web\.linkerd-viz\.svc|\[::1\])(:\d+)?$/ and has been denied for security reasons.
```

## Solution
Get the full install `yaml` manifest with the command:
```sh
linkerd viz install > linkerd-viz-install.yaml
```

If you want to completely disable the Host header check, simply use a catch-all regexp `.*` for `-enforced-host`. I'm using this *oneliner* to change the regex. You can use any editor, the argument is at line 1303 for version 2.14.7.
```sh
sed -i 's/\(.*enforced-host=\).*/\1.*/' linkerd-viz-install.yaml
```

Install the Linkerd viz extension fix with the command:
```sh
kubectl apply -f linkerd-viz-install.yaml
```

The service will have revert to `ClusterIP`, apply this patch to convert it to `Load Balancer`:
```sh
kubectl patch services -n linkerd-viz web --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"},{"op":"add","path":"/spec/allocateLoadBalancerNodePorts","value":false}]'
```

## After upgrading

> [!IMPORTANT]  
> After upgrading Linkerd, I found that all my service mesh were still using the old version of the proxy. To force them to use the new one, just `uninject` and re `inject` Linkerd. Here's an example for the `emojivoto` application.

Verify that all service mesh are using the new version of the proxy.
```sh
kubectl get pods -A -o jsonpath='{range .items[*]}{"pod: "}{.metadata.name}{"\n"}{range .spec.containers[*]}{"\tname: "}{.name}{"\n\timage: "}{.image}{"\n"}{end}'
kubectl get -n emojivoto deploy -o yaml | linkerd uninject - | kubectl apply -f -
# Wait till all the Pods are uninjected. Use Linkerd Viz
kubectl get -n emojivoto deploy -o yaml | linkerd inject - | kubectl apply -f -
```
