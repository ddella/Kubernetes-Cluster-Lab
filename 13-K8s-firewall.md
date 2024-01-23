# Firewall

## Edit firewall rules
All the firewall rules are in the file `/etc/iptables/rules.v4`.
```sh
sudo vi /etc/iptables/rules.v4
```

## br_bastion_1
Those are the rules for the `bastion` host subnet.
```
#  ZERO TRUST - br_bastion_1
-A OUTPUT -o br_bastion_1 -s 0/0 -d 0/0 -p tcp -m tcp --dport 22 -j ACCEPT
-A OUTPUT -o br_bastion_1 -p icmp --icmp-type 8 -s 0/0 -d 0/0 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -o br_bastion_1 -j REJECT --reject-with icmp-port-unreachable
```

You can apply the rules with the command:
```sh
sudo iptables-restore /etc/iptables/rules.v4
```

You can verify the rules with the command:
```sh
sudo iptables -L -n -v
```

```
Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         
  159 15814 ACCEPT     tcp  --  *      br_bastion_1  0.0.0.0/0            0.0.0.0/0            tcp dpt:22
    4   336 ACCEPT     icmp --  *      br_bastion_1  0.0.0.0/0            0.0.0.0/0            icmptype 8 state NEW,RELATED,ESTABLISHED
    0     0 REJECT     all  --  *      br_bastion_1  0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable
```
