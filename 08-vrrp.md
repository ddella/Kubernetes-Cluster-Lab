<a name="readme-top"></a>

# Keepalived: Basic configuration
In this tutorial, we'll explore the fundamentals of `Keepalived` installation and configuration for a simple two nodes Nginx load balancer (API Reverse Proxy) in Active-Passive configuration.

I assume you know how to configure an Nginx as either a layer 4 or layer 7 load balancer. If not I have a very sample configuration example at the end (<a href="#nginx">Nginx configuration</a>)

## What is `keepalived`
`keepalived` is used for IP failover between two servers. Its facilities for load balancing and high-availability to Linux-based infrastructures. It worked with VRRP (Virtual Router Redundancy Protocol) protocol. In this tutorial, we will configured IP failover between two Linux systems running Nginx as a load balancer for a web server.

## High Level Diagram
For this scenario, we have two Ubuntu servers that will run `keepalived` and share a VIP.

|Role|FQDN|IP|OS|Kernel|RAM|vCPU|Node|
|----|----|----|----|----|----|----|----|
|Load Balancer (VIP)|k8s1api.kloud.lan|10.101.1.10|Ubuntu 22.04.3|6.6.1|2G|2|N/A|
|Load Balancer|k8s1vrrp1.kloud.lan|10.101.1.11|Ubuntu 22.04.3|6.6.1|2G|2|pve1|
|Load Balancer|k8s1vrrp2.kloud.lan|10.101.1.12|Ubuntu 22.04.3|6.6.1|2G|2|pve2|

![High Level](images/keepalived01.jpg)

# Install Keepalived (master and slave)
Let's get our hands dirty and learn about the installation and basic configuration of `keepalived` to server a simple web server. This section applies to both server, `k8s1vrrp1` and `k8s1vrrp2`.

This is a short guide on how to install `keepalived` package on Ubuntu 22.04:
```sh
sudo nala update && sudo nala install keepalived
```

**DON'T DO THIS** but I couldn't help myself and I did it 😉 I downloaded the latest `.deb` package, extracted the binary file and copied it to `/usr/sbin/`. This should **NEVER BE DONE IN PRODUCTION** but the only dependencie not met is `libsnmp40`, so I decided to try it 😀
```sh
curl -LO http://security.ubuntu.com/ubuntu/pool/main/k/keepalived/keepalived_2.2.8-1_amd64.deb
# sudo apt-get install ./keepalived_2.2.8-1_amd64.deb
dpkg-deb --extract keepalived_2.2.8-1_amd64.deb keepalived
sudo mv /usr/sbin/keepalived /usr/sbin/keepalived-2-2-4
sudo cp keepalived/usr/sbin/keepalived /usr/sbin/.
```

With the latest release, I got rid of the warning:
```
keepalived.service: Got notification message from PID 8018, but reception only permitted for main PID 8017
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Configure `keepalived` on `k8s1vrrp1`
Create a Keepalived configuration file named `/etc/keepalived/keepalived.conf` on `k8s1vrrp1`.

> [!NOTE]  
> Make sure you have all you DNS records for the cluster. I'm using it to set the `VIP` in `keepalived` configuration file.

```sh
INTERFACE=enp1s0f0
VIP=$(dig +short +search k8s1api | tail -1)
SUBNET_MASK=24

cat <<EOF | sudo tee /etc/keepalived/keepalived.conf > /dev/null
global_defs {
  # optimization option for advanced use
  max_auto_priority
  enable_script_security
  script_user nginx  
}

# Script to check whether Nginx is running or not
vrrp_script check_nginx {
  script "/etc/keepalived/check_nginx.sh"
  interval 3
}

vrrp_instance VRRP_1 {
  state MASTER
  interface ${INTERFACE}
  virtual_router_id 70
  priority 255
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass secret
  }
  virtual_ipaddress {
    ${VIP}/${SUBNET_MASK}
  }
  # Use the script above to check if we should fail over
  track_script {
    check_nginx
  }
}
EOF
```

Create the script that checks if Nginx is running:
```sh
cat <<'EOF' | sudo tee /etc/keepalived/check_nginx.sh > /dev/null
#!/bin/sh
if [ -z "$(pidof nginx)" ]; then
  exit 1
fi
EOF
```

Set owner/permission for the script and restart `keepalived`:
```sh
sudo chown nginx:nginx /etc/keepalived/check_nginx.sh
sudo chmod 700 /etc/keepalived/check_nginx.sh 
sudo systemctl restart keepalived
sudo systemctl status keepalived
```

`keepalived `Parameters:

- state MASTER/BACKUP: the state that the router will start in.
- interface ens3: interface VRRP protocol messages should flow.
- virtual_router_id: An ID that both servers should agreed on.
- priority: number for master/backup election – higher numerical means higher priority.
- advert_int: backup waits this long (multiplied by 3) after messages from master fail before becoming master
- authentication: a clear text password authentication, no more than 8 caracters.
- virtual_ipaddress: the virtual IP that the servers will share
- track_script: Check if `Nginx` is running, if not `keepalived` fail to the backup

With the above configuration in place, you can start Keepalived on both servers using `systemctl start keepalived` and observe the IP addresses on each machine. Notice that `k8s1vrrp1` has started up as the VRRP master and owns the shared IP address (192.168.13.71), while `k8s1vrrp2` IP addresses remain unchanged:

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Configure `keepalived` on `k8s1vrrp2`
Create a Keepalived configuration file named `/etc/keepalived/keepalived.conf` on `k8s1vrrp2`. The only parameter to change here is the `state`.
```sh
INTERFACE="enp1s0f0"
VIP=$(dig +short +search k8s1api | tail -1)
SUBNET_MASK="24"
SECRET="secret"

cat <<EOF | sudo tee /etc/keepalived/keepalived.conf > /dev/null
global_defs {
  # optimization option for advanced use
  max_auto_priority
  enable_script_security
  script_user nginx  
}

# Script to check whether Nginx is running or not
vrrp_script check_nginx {
  script "/etc/keepalived/check_nginx.sh"
  interval 3
}

vrrp_instance VRRP_1 {
  state MASTER
  interface ${INTERFACE}
  virtual_router_id 70
  priority 250
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass ${SECRET}
  }
  virtual_ipaddress {
    ${VIP}/${SUBNET_MASK}
  }
  # Use the script above to check if we should fail over
  track_script {
    check_nginx
  }
}
EOF
```

Create the script that checks if Nginx is running:
```sh
cat <<'EOF' | sudo tee /etc/keepalived/check_nginx.sh > /dev/null
#!/bin/sh
if [ -z "$(pidof nginx)" ]; then
  exit 1
fi
EOF
```

Set owner/permission for the script and restart `keepalived`:
```sh
sudo chown nginx:nginx /etc/keepalived/check_nginx.sh
sudo chmod 700 /etc/keepalived/check_nginx.sh 
sudo systemctl restart keepalived
sudo systemctl status keepalived
```

- `k8s1vrrp1` should start as the VRRP master and owns the shared VIP address 192.168.13.70
- `k8s1vrrp2` should start as the VRRP backup

You can check with the command:
```sh
ip add show dev enp1s0f0 | grep inet | grep -v inet6
```

Output for the primary:
```
inet 10.101.1.11/24 brd 10.101.1.255 scope global enp1s0f0
inet 10.101.1.10/24 scope global secondary enp1s0f0
```

Output for the secondary:
```
inet 10.101.1.12/24 brd 10.101.1.255 scope global enp1s0f0
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Verify keepalived and VRRP
## Logs
### Filter Service
The `-u` flag is used to specify the service you are looking for:
```sh
journalctl -u keepalived.service
```

### View log details
Detailed messages with explanations can be viewed by adding the `-x` to help you understand the logs:
```sh
journalctl -u keepalived.service -x
```

## View logs between a given time period
```sh
journalctl -u keepalived.service  --since "2023-07-23 10:27:00" --until "2023-07-23 10:28:00"
```

View logs from yesterday until now:
```sh
journalctl --since yesterday --until now
```

## IP address
If you check the IP addresses on the master node, you should see the VRRP address:
```sh
ip -brief address show
```

>You won't see the VRRP address for `backup` node in normal situation.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Simulate a failure
Let's simulate a failure by shutting the service `keepalived` on the primary node, `k8s1vrrp1`, like so:
```sh
sudo systemctl stop keepalived
```

If you monitor the logs on the backup node, `k8s1vrrp2`, with the command:
```sh
journalctl -f -u keepalived
```

You should see a event like this one:
```
Jul 23 11:13:57 k8s1vrrp2.kloud.lan Keepalived_vrrp[2112]: (VRRP_1) Entering MASTER STATE
```

If you check the IP addresses on the backup node, you should now see the VRRP address:
```sh
ip -brief address show
```

Output on backup node with the master node "down":
```
lo               UNKNOWN        127.0.0.1/8 
ens33            UP             192.168.13.72/24 192.168.13.70/24
```

## Arp
From another server, **on the same subnet**, check the *arp* table with the command:
```sh
ip neighbor
```

Output when master node has the VRRP address:
```
192.168.13.70 dev ens33 lladdr 00:0c:29:07:df:d3 REACHABLE
192.168.13.71 dev ens33 lladdr 00:0c:29:07:df:d3 REACHABLE
192.168.13.72 dev ens33 lladdr 00:0c:29:6c:26:01 REACHABLE
```

Output when backup node has the VRRP address (master node down):
```
192.168.13.70 dev ens33 lladdr 00:0c:29:6c:26:01 REACHABLE
192.168.13.71 dev ens33 lladdr 00:0c:29:07:df:d3 REACHABLE
192.168.13.72 dev ens33 lladdr 00:0c:29:6c:26:01 REACHABLE
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Test
I've build, a long time ago, an Nginx web server with some PHP pages that returns connection information. I started one container to test `keepalived` with the command:
```sh
docker run --rm -d -p 8080:80 -p 8443:443 -p 1234:1234 --name web \
--hostname=webserver \
--env TZ='EAST+5EDT,M3.2.0/2,M11.1.0/2' \
--env TIMEZONE='America/New_York' \
--env TCP_PORT=1234 \
--env UDP_PORT=5678 \
php82_nginx125:3.18.2
```

>You need to have the image `php82_nginx125:3.18.2` locally in Docker, it's not on Docker Hub. See my tutorial [here](https://github.com/ddella/PHP8-Nginx/) to build the image.

### From `k8s1vrrp1` check the load balancer log with the command:
```sh
tail -f /var/log/nginx/k8sapi.access.log
```

### From `k8s1vrrp2` check the load balancer log with the command:
```sh
tail -f /var/log/nginx/k8sapi.access.log
```

### From a client machine, try to access the test page continuously, by using the VIP, with the command:
```sh
while true; do curl http://192.168.13.70:8080/test.php; sleep 1.0; done
```

>Hit `ctrl-C` to stop

### Simulate a failure on `k8s1vrrp1` with the command:
```sh
sudo systemctl stop keepalived
```

### Restore the service on `k8s1vrrp1` with the command:
```sh
sudo systemctl stop keepalived
```

While both load balancer are functionning, you will see, from the logs, that `k8s1vrrp1` is servicing the client requests. When `k8s1vrrp1` failed, you will see, from the logs, that `k8s1vrrp2` is servicing the client requests.

# Cleanup
Stop and remove the container with the command:
```sh
docker rm -f web
```

In case you want to uninstall `keepalived`, use the commands below:
```sh
sudo apt remove keepalived
sudo apt autoclean && sudo apt autoremove
```

<a name="nginx"></a>

# Nginx Configuration - Layer 7
This is my Nginx configuration on both load balancers. This is a layer 7 load balancer or just an API gateway.

```sh
cat <<'EOF' | sudo tee /etc/nginx/conf.d/k8sapi.conf
upstream k8s-api-8080 {
    server 192.168.13.104:8080;
}
server {
    listen 8080;
    server_name k8sapi-vrrp.kloud.lan;

    location / {
      access_log      /var/log/nginx/keepalived.access.log;
      error_log       /var/log/nginx/keepalived.error.log;

      proxy_set_header   Host              $http_host;
      proxy_set_header   X-Real-IP         $remote_addr;
      proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto https;

      # round-robin load balancing
      proxy_pass          http://k8s-api-8080;
      proxy_read_timeout  90;
    }
}

upstream k8s-api-8443 {
    server 192.168.13.104:8443;
}
server {
    listen 8443 ssl;
    server_name k8sapi-vrrp.kloud.lan;

    ssl_certificate       /etc/ssl/certs/k8sapiserver.crt;
    ssl_certificate_key   /etc/ssl/private/k8sapiserver.key;

    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols  TLSv1.3 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;

    location / {
      access_log      /var/log/nginx/keepalived.access.log;
      error_log       /var/log/nginx/keepalived.error.log;

      proxy_set_header   Host              $http_host;
      proxy_set_header   X-Real-IP         $remote_addr;
      proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto https;

      proxy_ssl_certificate         /etc/ssl/certs/k8sapiclient.crt;
      proxy_ssl_certificate_key     /etc/ssl/private/k8sapiclient.key;
      proxy_ssl_protocols           TLSv1.3 TLSv1.2;
      proxy_ssl_ciphers             HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
      proxy_ssl_verify_depth  2;
      proxy_ssl_session_reuse on;
      # round-robin load balancing
      proxy_pass          https://k8s-api-8443;
      proxy_read_timeout  90;
    }
}
EOF
```

# Nginx Configuration - Layer 4
This is my Nginx configuration on both load balancers. This is a layer 4 load balancer.

```sh
cat <<'EOF' | sudo tee /etc/nginx/tcpconf.d/k8sapi.conf
stream {
    log_format k8sapilogs '[$time_local] $remote_addr:$remote_port $server_addr:$server_port '
        '$protocol $status $bytes_sent $bytes_received '
        '$session_time';
    upstream k8s-api {
	server 192.168.13.104:8080;
    }
    server {
        listen 8080;

        proxy_pass k8s-api;
        access_log /var/log/nginx/keepalived.access.log k8sapilogs;
	error_log /var/log/nginx/keepalived.error.log warn;
    }
}
EOF
```

# Convert to Layer 7 Load Balancer
Just apply those changes to have Nginx act as a layer 7 load balancer. Apply this on `k8sapi` server:
```sh
sudo mv /etc/nginx/conf.d/k8sapi.conf.bak /etc/nginx/conf.d/k8sapi.conf
sudo mv /etc/nginx/tcpconf.d/k8sapi.conf /etc/nginx/tcpconf.d/k8sapi.conf.bak
sudo systemctl restart nginx
sudo systemctl status nginx
```
>Note: I prefer to have Nginx configured as a layer 7 load balancer because the logs are way more verbose since Nginx terminates the TLS session.

# Convert to Layer 4 Load Balancer
If you want to go back to Layer 4 Load Balancer, just apply those changes to have Nginx act as a layer 4 load balancer. Apply this on `k8sapi` server:
```sh
sudo mv /etc/nginx/conf.d/k8sapi.conf /etc/nginx/conf.d/k8sapi.conf.bak
sudo mv /etc/nginx/tcpconf.d/k8sapi.conf.bak /etc/nginx/tcpconf.d/k8sapi.conf
sudo systemctl restart nginx
sudo systemctl status nginx
```

# References
[GitHub](https://github.com/acassen/keepalived)  
[RedHat Simple Configuratiomn](https://www.redhat.com/sysadmin/keepalived-basics)  
[Flat Icon](https://www.flaticon.com/free-icons/user)  


