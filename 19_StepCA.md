# Smallstep
`step` is an open-source command-line tool for developers, operators, and security professionals to configure and automate the smallstep toolchain and a swiss-army knife 🧰 for day-to-day operations of open standard identity technologies.


## Install the CLI
get the latest version:
```sh
VER=$(curl -s https://api.github.com/repos/smallstep/cli/releases/latest | grep tag_name | cut -d '"' -f 4|sed 's/v//g')
echo $VER
```

Install the CLI in `/usr/local/bin/` with the commands:
```sh
curl -OL https://dl.smallstep.com/gh-release/cli/gh-release-header/v${VER}/step_linux_${VER}_amd64.tar.gz
tar -zxvf step_linux_${VER}_amd64.tar.gz
sudo install -g adm -o root step_${VER}/bin/step /usr/local/bin/.
```

Cleanup the binary downloaded in the step above:
```sh
rm -rf step_${VER}
rm -f step_linux_${VER}_amd64.tar.gz
unset VER
```

## Check
```sh
step version
```

Output:
```
Smallstep CLI/0.25.0 (linux/amd64)
Release Date: 2023-09-27T05:35:24Z
```

## `step` completion
Add bash completion for the current user ONLY with the command:
```sh
step completion bash >> ~/.bash_completion
```

Add bash completion for all the users with the command:
```sh
step completion bash | sudo tee /etc/profile.d/step_bash_completion.sh
```

# Create a Certificate Authority
https://smallstep.com/docs/step-cli/reference/certificate/create/

## Create a Root CA
```sh
step certificate create --profile root-ca "kloud.lan Root CA" root_ca.crt root_ca.key \
--no-password --insecure --crv=P-384 --kty=EC
```

> [!IMPORTANT]  
> Now you can store your `root_ca.key` in a safe place offline, because you'll only need the Root CA key to issue sign Intermediate CA certificates.

## Create an intermediate CA
```sh
step certificate create "Example Intermediate CA 1" \
intermediate_ca.crt intermediate_ca.key \
--profile intermediate-ca --ca ./root_ca.crt --ca-key ./root_ca.key \
--no-password --insecure --crv=P-384 --kty=EC
```

## Create a leaf certificate
Use your intermediate CA to sign leaf (end entity) certificates for your servers.

Create a leaf TLS certificate for `kloud.lan`, valid for a year:

```sh
step certificate create k8s1bastion1.kloud.lan \
k8s1bastion1.kloud.lan.crt k8s1bastion1.kloud.lan.key \
--profile leaf --not-after=8760h \
--no-password --insecure --crv=P-256 --kty=EC \
--ca ./intermediate_ca.crt --ca-key ./intermediate_ca.key
```

> [!NOTE]  
> If you want to automatically bundle the new leaf certificate with the signing intermediate certificate, use the `--bundle` flag.

##
```sh
step certificate verify k8s1bastion1.kloud.lan.crt --roots root_ca.crt,intermediate_ca.crt
```

> [!NOTE]  
> No output means certificate is valid

# Inspect an X.509 Certificate
```sh
step certificate inspect k8s1bastion1.kloud.lan.crt
```

