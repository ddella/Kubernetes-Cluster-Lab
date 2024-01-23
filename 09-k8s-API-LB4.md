<a name="readme-top"></a>

# Nginx as a load balancer
This section is about configuring an Nginx reverse proxy/load balancer to front the Kubernetes API server. We are building a K8s cluster in high availability with at least three (3) master node. When a request arrives for Kubernetes API, Nginx becomes a proxy and further forward that request to any healthy K8s Master node, then it forwards the response back to the client.

This assumes that:
- K8s API server runs on port 6443 with HTTPS
- All K8s Master node runs the API via the URL: http://<master node>:6443

Nginx will run on a bare metal/virtual Ubuntu server outside the K8s cluster.

##  What is a Reverse Proxy
Proxying is typically used to distribute the load among several servers, seamlessly show content from different websites, or pass requests for processing to application servers over protocols other than HTTP.

When NGINX proxies a request, it sends the request to a specified proxied server, fetches the response, and sends it back to the client.

In this tutorial, Nginx Reverse proxy receive inbound `HTTPS` requests and forward those requests to the K8s master nodes. It receives the outbound `HTTP` response from the API servers and forwards those requests to the original requester.

## Installing from the Official NGINX Repository
NGINX Open Source is available in two versions:

- **Mainline** - Includes the latest features and bug fixes and is always up to date. It is reliable, but it may include some experimental modules, and it may also have some number of new bugs.
- **Stable** - Doesn't include all of the latest features, but has critical bug fixes that are always backported to the mainline version. We recommend the stable version for production servers.

Of course I chooses the `Mainline` version to get all the latest features 😀

Install the prerequisites:
```sh
sudo nala install curl gnupg2 ca-certificates lsb-release debian-archive-keyring
```

Import an official nginx signing key so `apt` could verify the packages authenticity. Fetch the key with the command:
```sh
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
| sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
```
Verify that the downloaded file contains the proper key:
```sh
gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
```

If the output is different **stop** and try to figure out what happens:
```
pub   rsa2048 2011-08-19 [SC] [expires: 2024-06-14]
      573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62
uid                      nginx signing key <signing-key@nginx.com>
```

Run the following command to use `mainline` Nginx packages:
```sh
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
https://nginx.org/packages/mainline/ubuntu/ `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
```

Set up repository pinning to prefer our packages over distribution-provided ones:
```sh
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
| sudo tee /etc/apt/preferences.d/99nginx
```

Update the repo and install NGINX:
```sh
sudo nala update
sudo nala install nginx
```

## Checking Nginx
Start and check that Nginx is running:
```sh
sudo systemctl start nginx
sudo systemctl status nginx
```

Try with `cURL`, you should receive the Nginx welcome page:
```sh
curl http://127.0.0.1
```

## Configure Nginx for layer 4 Load Balancing
This will be the initial configuration of Nginx. I've never been able to bootstrap a Kubernetes Cluster with a layer 7 Load Balancer due the `mTLS` configuration.

Create another directory for our layer 4 Load Balancer. The reason is that the directive in `nginx.conf` file for our layer 4 and layer 7 load balancer are in different section:
```sh
sudo mkdir /etc/nginx/tcpconf.d/
```

Create the configuration file. This one will be active:
```sh
sudo cat <<'EOF' | sudo tee /etc/nginx/tcpconf.d/k8s1api.conf >/dev/null
stream {
    log_format k8s1apilogs '[$time_local] $remote_addr:$remote_port $server_addr:$server_port '
        '$protocol $status $bytes_sent $bytes_received '
        '$session_time';
    upstream k8s1-api {
        server k8s1master1.kloud.lan:6443;
        server k8s1master2.kloud.lan:6443;
        server k8s1master3.kloud.lan:6443;
        server k8s1master4.kloud.lan:6443;
        server k8s1master5.kloud.lan:6443;
        server k8s1master6.kloud.lan:6443;
    }
    server {
        listen 6443;

        proxy_pass k8s1-api;
        access_log /var/log/nginx/k8s1api.access.log k8s1apilogs;
        error_log /var/log/nginx/k8s1api.error.log warn;
    }
}
EOF
```
> [!IMPORTANT]  
>  Don't forget the quote around `'EOF'`. We need the variables inside the file not the values of those variables

Add a directive in the `nginx.conf` to parse all the `.conf` file in the new directory we created:
```sh
cat <<EOF | sudo tee -a /etc/nginx/nginx.conf >/dev/null
include /etc/nginx/tcpconf.d/*.conf;
EOF
```

**Important**: Verify Nginx configuration files with the command:
```sh
sudo nginx -t
```
> [!IMPORTANT]  
>  If you don't use `sudo`, you'll get some weird alerts

Restart and check status Nginx server:
```sh
sudo systemctl restart nginx
sudo systemctl status nginx
```

## Verify the load balancer
On the server `k8s1api.kloud.lan` check Nginx logs with the command:
```sh
sudo tail -f /var/log/nginx/k8s1api.error.log
```

When a client tries to connect, you should see this output. Since we don't have a K8s cluster yet, Nginx will try all the servers in the group and it will receive a `Connection refused`.
```
2023/11/17 13:07:58 [error] 5542#5542: *24 connect() failed (111: Connection refused) while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.203:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [warn] 5542#5542: *24 upstream server temporarily disabled while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.203:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [error] 5542#5542: *24 connect() failed (111: Connection refused) while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.101:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [warn] 5542#5542: *24 upstream server temporarily disabled while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.101:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [error] 5542#5542: *24 connect() failed (111: Connection refused) while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.102:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [warn] 5542#5542: *24 upstream server temporarily disabled while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.102:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [error] 5542#5542: *24 connect() failed (111: Connection refused) while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.103:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [warn] 5542#5542: *24 upstream server temporarily disabled while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.103:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [error] 5542#5542: *24 connect() failed (111: Connection refused) while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.201:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [warn] 5542#5542: *24 upstream server temporarily disabled while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.201:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [error] 5542#5542: *24 connect() failed (111: Connection refused) while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.202:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
2023/11/17 13:07:58 [warn] 5542#5542: *24 upstream server temporarily disabled while connecting to upstream, client: 10.103.1.103, server: 0.0.0.0:6443, upstream: "10.101.1.202:6443", bytes from/to client:0/0, bytes from/to upstream:0/0
```

From another machine, try to connect to the K8s API loab balancer, with the command (no need for the `--insecure` flag):
```sh
curl --max-time 3 https://k8s1api.kloud.lan:6443
```

Output on the client:
```
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>nginx/1.25.1</center>
</body>
</html>
```

>Both outputs are normal, since we don't have a K8s master node yet 😀

# Conclusion
You have a Ubuntu server that acts as a load balancer for all API requests to K8s (ex.: `kubectl` command).

# References
[Nginx Load Balancer](https://nginx.org/en/docs/http/load_balancing.html)  
[Installing NGINX Open Source](https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/)  
