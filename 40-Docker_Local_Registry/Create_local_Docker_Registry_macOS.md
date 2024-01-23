# Create a local Docker Registry on Mac
This quick tutorial will show how to push a docker image to a private repository on a macOS.

I have a docker image tagged as `dnsutils/1.0.0` that I want to use in my local Kubernetes Cluster. I want to host my Docker images local.

### Definition
"Registry" versus "Repository".
A repository is a place where data is actually stored. A registry is a collection of pointers to that data.
For example, a library's card catalog is the registry you would consult to find the location of the book you need. The library's actual bookshelves are its repository.

## Prepare data directory for Docker Registry
Create a data directory structure for our Docker Registry.
```sh
mkdir -p ${HOME}/docker-registry/{auth,certs,data}
```

The directory structure should look like this:
```
|____data
| |____auth
| | |____registry.password
| |____docker-compose.yml
| |____certs
| |____data
| | |____docker
| | | |____registry
| | | | |____v2
| | | | | |____repositories
| | | | | |____blobs
```

## HTTPS
You can allow outside access to your self-hosted Registry with `https`. You will need to generate a TLS certificate and have it signed by Kubernetes.

Will generate a certificate signed by Kubernetes. You could do this in multiple ways, I've choosen to have Kubernetes signed the TLS server certificate that we will installed for the Docker Registry container.

The steps are as followK
- Generate TLS private key with `openssl`
- Generate s certificate signing request (csr) with `openssl`
- Send the csr to Kubernetes to have it sign by the CA
- Approve the csr
- Get the certificate from Kubernetes
- Copy the certificate/private where Docker Registry container can read them

Generate TLS private key and csr with `openssl`. Can be done on any machine with `openssl`.
```sh
openssl ecparam -name prime256v1 -genkey -out repo-key.pem

openssl req -new -sha256 -key repo-key.pem -subj "/C=CA/ST=QC/L=Montreal/O=system:nodes/OU=IT/CN=system:node:" \
-addext "subjectAltName = DNS:localhost,DNS:*.localhost,DNS:dkr-registry.kloud.lan" \
-addext "keyUsage = digitalSignature, keyEncipherment" \
-addext "basicConstraints = CA:FALSE" -addext "extendedKeyUsage = serverAuth" -addext "subjectKeyIdentifier = hash" -out repo-csr.pem
```

Send the csr to Kubernetes to have it sign by the CA
```sh
cat <<EOF > repo-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: repo-csr
spec:
  request: $(cat repo-csr.pem | base64 | tr -d '\n')
  signerName: kubernetes.io/kubelet-serving
  usages:
  - server auth
  - digital signature
  - key encipherment
EOF
kubectl create -f repo-csr.yaml
kubectl get csr
```

Approve the CSR and get it back
```sh
kubectl certificate approve repo-csr
kubectl get csr
kubectl get csr repo-csr -o jsonpath='{.status.certificate}'| base64 -d > repo-crt.pem
cat repo-crt.pem
kubectl delete csr repo-csr
```

Copy the certificate and private key to you Docker Registry Directory:
```sh
scp daniel@k8s1bastion1.kloud.lan:/home/daniel/Registry/repo-{crt,key}.pem certs/.
```

> [!IMPORTANT]  
> Read [this](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#kubernetes-signers) document for the `signerName` values and the `usages` values. Failure to have the correct combination will result in a failed certificate.

Make sur you add the Kubernetes CA certificate in your local certificate store or you'll get this error when you start the Registry container:
`... failed to verify certificate: x509: certificate signed by unknown authority`

## Create a directory to store authentication data
Create a directory, inside the `docker-registry` directory to store authentication data. Docker Registry requires a username/password to access it. So, we need to create a file using `htpasswd` command. `htpasswd` is used to create and update a *flat-files* used to store usernames and password for basic authentication of HTTP users. The file, `registry.password`, will contain the credentials for our Registry.

Create the *flat-files* to store the username/password.
```sh
htpasswd -Bc auth/registry.password admin
```

`htpasswd` will create a file called `registry.password`.
`admin` is the user which we are creating for our Registry.

## Create Registry Container
Create a `docker-compose.yml` file in which you will define your Docker Registry parameters like port, data volume, etc. Using this file, Docker will pull the registry image from Docker Hub, in this case `registry:2.8.3`. This is the *server* that will answer `pull/push` requests. I'm using version 2.8.3. Please check for the latest release.

```sh
cat <<EOF > docker-compose.yml
version: '3'
services:
  registry:
    image: registry:2.8.3
    ports:
    - "5001:5000"
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/registry.password
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /data
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/repo-crt.pem
      REGISTRY_HTTP_TLS_KEY: /certs/repo-key.pem
    volumes:
      - ./auth:/auth
      - ./certs:/certs
      - ./data:/data
EOF
```

> [!NOTE]  
> Check the version of `registry` at https://hub.docker.com/_/registry

## Run docker-compose up command to start your Registry
You should be back at the `data` directory. Run `docker compose up` command. This command will read your `docker-compose.yml` file and start your Docker registry container.
```sh
docker compose -f docker-compose.yml --project-name registry up -d
```

Test with `docker login`:
```sh
docker login dkr-registry.kloud.lan:5001 -u admin
```

Output:
```
Password: 
Login Succeeded
```

Test with `curl`:
```sh
curl -u admin:<YOU_PASSWORD> -H GET "https://dkr-registry.kloud.lan:5001/v2/_catalog"
```

> [!WARNING]  
> This will expose your password in `~/.bash_history` 😉

Output:
```
{"repositories":[]}
```

## Push an image
Let's *push* an image in our new local Docker registry. You need to tag your image correctly first with your `registryhost:`
```sh
docker tag [OPTIONS] IMAGE[:TAG] [REGISTRYHOST/][USERNAME/]NAME[:TAG]
```

Then use `docker push` using that same tag.
```sh
docker push NAME[:TAG]
```

My local image is `dnsutils2:2.0.0` and my local registry is `dkr-registry.kloud.lan:5001`

Tag the image:
```sh
docker tag dnsutils2:2.0.0 dkr-registry.kloud.lan:5001/dnsutils2:2.0.0
```

Push the image:
```sh
docker push dkr-registry.kloud.lan:5001/dnsutils2:2.0.0
```

Output:
```
The push refers to repository [dkr-registry.kloud.lan:5001/dnsutils2]
762e7e988b00: Pushed 
5af4f8f59b76: Pushed 
2.0.0: digest: sha256:b8978f8e20f6309349a25d7997ed3d0474abf9941bbd886de629e4c0238d5e97 size: 739
```

Now let's get the *catalog* to see if we have something:
```sh
curl -u admin:<YOU_PASSWORD> -H GET "https://dkr-registry.kloud.lan:5001/v2/_catalog"
```

Output:
```
{"repositories":["dnsutils2"]}
```

You now have a local repository for all you Docher images 🎉🎉🎉

# TL;DR
```
docker login <REGISTRY_HOST>:<REGISTRY_PORT>
docker tag <IMAGE_ID> <REGISTRY_HOST>:<REGISTRY_PORT>/<APPNAME>:<APPVERSION>
docker push <REGISTRY_HOST>:<REGISTRY_PORT>/<APPNAME>:<APPVERSION>
```

If you docker registry is private, running and self hosted you need those three commands:
```sh
docker login dkr-registry.kloud.lan:5001 -u admin
docker tag dnsutils2:2.0.0 dkr-registry.kloud.lan:5001/dnsutils2:2.0.0
docker push dkr-registry.kloud.lan:5001/dnsutils2:2.0.0
```

# References
[Incomplete but the best I've seen](https://shashanksrivastava.medium.com/create-a-local-docker-registry-on-mac-74cbeac86bfc)


# Kubernetes
```sh
kubectl create secret -n dnsutils docker-registry docker-registry --docker-server=dkr-registry.kloud.lan:5001 --docker-username=admin --docker-password=lfdmea7h
```

```sh
kubectl get secret -n dnsutils -o yaml
```

The output is similar to this:
```
apiVersion: v1
items:
- apiVersion: v1
  data:
    .dockerconfigjson: eyJhd...uMTY4LjEz...aa2JXVmhOMmc9In19fQ==
  kind: Secret
  metadata:
    creationTimestamp: "2024-01-04T21:00:18Z"
    name: docker-registry
    namespace: dnsutils
    resourceVersion: "2141615"
    uid: 7bd90224-2cfd-4453-96c8-3193b5b80f9b
  type: kubernetes.io/dockerconfigjson
kind: List
metadata:
  resourceVersion: ""
```

Get the secret back. You password will be printed on the screen in clear.
```sh
kubectl get secret -n dnsutils docker-registry --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
```

The output is similar to this:
```
{"auths":{"192.168.13.206:5005":{"username":"admin","password":"......","auth":"YWRtaW4...N2g="}}}
```

Decode the `auth` field:
```sh
echo "YWRtaW4...N2g=" | base64 --decode
```

https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/

# Start the Pod

## Start Pods
Start the Pod in your Kubernetes Cluster
```sh
cat <<EOF > dnsutils.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: dnsutils
  namespace: dnsutils
spec:
  containers:
  - name: dnsutils
    image: dkr-registry.kloud.lan:5001/dnsutils2:2.0.0
    command:
      - sleep
      - "infinity"
    imagePullPolicy: IfNotPresent
  imagePullSecrets:
  - name: docker-registry
  restartPolicy: Always
EOF

kubectl apply -f dnsutils.yaml
```

https://microk8s.io/docs/registry-private

## Verification
Check that your Pod is running. Of course it doesn't work 😂
```sh
kubectl get pods dnsutils -n dnsutils
kubectl describe pods dnsutils -n dnsutils
```

You get the message:
```
  Warning  Failed     11s   kubelet            Failed to pull image "dkr-registry.kloud.lan:5001/dnsutils2:2.0.0": failed to pull and unpack image "dkr-registry.kloud.lan:5001/dnsutils2:2.0.0": failed to resolve reference "dkr-registry.kloud.lan:5001/dnsutils2:2.0.0": failed to do request: Head "https://dkr-registry.kloud.lan:5001/v2/dnsutils2/manifests/2.0.0": tls: failed to verify certificate: x509: certificate signed by unknown authority
  Warning  Failed     11s   kubelet            Error: ErrImagePull
  Normal   BackOff    11s   kubelet            Back-off pulling image "dkr-registry.kloud.lan:5001/dnsutils2:2.0.0"
  Warning  Failed     11s   kubelet            Error: ImagePullBackOff
```

Even though we signed our certificate by Kubernetes CA, it's `containerd` that pulls the image and it doesn't trust the Kubernetes CA. So let's add the CA to the nodes of your Cluster.

This step requires to have access to your nodes, master and worker, of your Kubernetes Cluster. Just connect to them via ssh and add the given certificate to the cert store.

> [!IMPORTANT]  
>  You need to add the Certificate Authority to **every** node in your cluster. Failure to do so will result is some nodes being able to pull the images and some not.

All my nodes run on Ubuntu. Copy your CA to the target location:
```
/usr/local/share/ca-certificates
```

Update the trusted store with the command:
```sh
sudo update-ca-certificates
```

Output from the command above:
```
Updating certificates in /etc/ssl/certs...
rehash: warning: skipping ca-certificates.crt,it does not contain exactly one certificate or CRL
1 added, 0 removed; done.
Running hooks in /etc/ca-certificates/update.d...
done.
```

Restart `containerd` with the following command:
```sh
sudo systemctl restart containerd
```

> [!IMPORTANT]  
> Repeat those steps for all nodes, master and worker, in your the cluster.

# FAQ
Common errors
### Registry container not running
```
daniel@MacBook-Dan data % docker login dkr-registry.kloud.lan:5001 -u admin
Password: 
Error response from daemon: Get "https://dkr-registry.kloud.lan:5001/v2/": dialing dkr-registry.kloud.lan:5001 with direct connection: connecting to 192.168.13.206:5001: dial tcp 192.168.13.206:5001: connect: connection refused
```

### Add the chain of trust to your local trust store (on macOS, it's KeyChain)
```
daniel@MacBook-Dan data % docker login dkr-registry.kloud.lan:5001 -u admin
Password: 
Error response from daemon: Get "https://dkr-registry.kloud.lan:5001/v2/": tls: failed to verify certificate: x509: certificate signed by unknown authority
```

### Server certificate need to have `extendedKeyUsage = serverAuth` attribute `clientAuth` will give you the below error
```
daniel@MacBook-Dan data % docker login dkr-registry.kloud.lan:5001 -u admin
Password: 
Error response from daemon: Get "https://dkr-registry.kloud.lan:5001/v2/": tls: failed to verify certificate: x509: certificate specifies an incompatible key usage
```

# Docker Daemon - HTTP (Don't do this 😉)
If you want to use the registry via `http` instead of `https`, follow those steps.

If you try to access the API with `http`, the default configuration in Docker Desktop that will throw this error:.
```
Head "https://dkr-registry.kloud.lan:5005/v2/dnsutils/manifests/latest": http: server gave HTTP response to HTTPS client
```

The quick fix is to edit the file `$HOME/.docker/daemon.json`, add the following `json` configuration and **restart** Docker Desktop.

ADD this at the bottom of the file:
```json
  "experimental": false,
  "insecure-registries": [
    "dkr-registry.kloud.lan:5001"
  ]
```

> [!IMPORTANT]  
> I'm using port `5001` because macOS uses port `5000` for something else. See the error below if you try to use port `5000` for your local Docker registry:
> `docker: Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:5000 -> 0.0.0.0:0: listen tcp 0.0.0.0:5000: bind: address already in use.`
> `dkr-registry.kloud.lan` resolves to the IP address of Docker Deskptop since the registry is a container.

Check that the configuration has been applied with the command:
```
docker info
```

Look near the bottom for the output:
```
[...]
 Insecure Registries:
  dkr-registry.kloud.lan:5001
  hubproxy.docker.internal:5555
  127.0.0.0/8
```

## Tell `containerd` to use HTTP (DON'T DO THIS IF USING HTTPS)
If you will use Kubernetes to access this Docker private Repo with `http`, you have to tell `containerd`. This is the error you'll get if you keep the default configuration.

```
Error:
`failed to do request: Head "https://dkr-registry.kloud.lan:5001/v2/dnsutils/manifests/1.0.0"`
```

This as to be done on **every** master and worker node in your Kubernetes Cluster:
```sh
sudo vi /etc/containerd/config.toml
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.13.206:5005"]
        endpoint = ["http://dkr-registry.kloud.lan:5001"]
```

Restart the service:
```sh
sudo systemctl restart containerd
```
