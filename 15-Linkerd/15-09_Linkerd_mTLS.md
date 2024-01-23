# Generating your own mTLS root certificates
In order to support mTLS connections between meshed pods, Linkerd needs a trust anchor certificate and an issuer certificate with its corresponding key.

You can generate these certificates using a tool like openssl or step. All certificates must use the ECDSA P-256 algorithm which is the default for step.

# Generating the certificates with openSSL
## Create a Root certificate and key
```sh
# Create the private key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -pkeyopt ec_param_enc:named_curve -out ca-key.pem

# Create the certificate
openssl req -new -sha256 -x509 -key ca-key.pem -days 7300 \
-subj "/C=CA/ST=QC/L=Montreal/O=RootCA/OU=IT/CN=Linkerd CA Root CA" \
-addext "subjectAltName = DNS:localhost,DNS:*.localhost,DNS:root.linkerd.cluster.local,IP:127.0.0.1" \
-addext "basicConstraints = critical,CA:TRUE" \
-addext "keyUsage = critical, digitalSignature, cRLSign, keyCertSign" \
-addext "subjectKeyIdentifier = hash" \
-addext "authorityKeyIdentifier = keyid:always, issuer" \
-out ca-crt.pem
```

## Issuer certificate and key
Then generate the intermediate certificate and key pair that will be used to sign the Linkerd proxies CSR.
```sh
# Create the private key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -pkeyopt ec_param_enc:named_curve -out int-key.pem

# Create the certificate signed by the CA
openssl req -new -sha256 -key int-key.pem \
-subj "/C=CA/ST=QC/L=Montreal/O=IntermediateCA/OU=IT/CN=Linkerd CA Intermediate CA" \
-addext "subjectAltName = DNS:localhost,DNS:*.localhost,DNS:identity.linkerd.cluster.local,IP:127.0.0.1" \
-addext "basicConstraints = critical, CA:TRUE, pathlen:0" \
-addext "keyUsage = critical, digitalSignature, cRLSign, keyCertSign" \
-addext "subjectKeyIdentifier = hash" \
-out int-csr.pem

openssl x509 -req -sha256 -days 365 -in int-csr.pem -CA ca-crt.pem -CAkey ca-key.pem -CAcreateserial \
-extfile - <<<"subjectAltName = DNS:localhost,DNS:*.localhost,DNS:identity.linkerd.cluster.local,IP:127.0.0.1
basicConstraints = critical, CA:TRUE, pathlen:0
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
keyUsage = critical, digitalSignature, cRLSign, keyCertSign" \
-out int-crt.pem
```
