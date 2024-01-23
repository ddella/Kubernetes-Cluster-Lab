# What is Cilium
Cilium is open source software for transparently securing the network connectivity between application services deployed using Linux container management platforms like Docker and Kubernetes.

At the foundation of Cilium is a new Linux kernel technology called `eBPF`, which enables the dynamic insertion of powerful security visibility and control logic within Linux itself. Because `eBPF` runs inside the Linux kernel, Cilium security policies can be applied and updated without any changes to the application code or container configuration.

# What is Hubble
Hubble is a fully distributed networking and security observability platform. It is built on top of Cilium and `eBPF` to enable deep visibility into the communication and behavior of services as well as the networking infrastructure in a completely transparent manner.

By building on top of Cilium, Hubble can leverage `eBPF` for visibility. By relying on `eBPF`, all visibility is programmable and allows for a dynamic approach that minimizes overhead while providing deep and detailed visibility as required by users. Hubble has been created and specifically designed to make best use of these new `eBPF` powers.

# What is Helm
`helm` is the popular Kubernetes package manager.

# What is cilium-cli
`cilium-cli` is a purpose-built tool to install and manage Cilium. 

# Cilium Installation
There's two ways to install Cilium:
- Cilium Installation using CLI
- Cilium Installation using Helm

The method with Helm gives you more control on how Cilium will be installed and configured.

# Cilium Installation using Helm
Use [this](01-2-Install-Cilium-Helm.md) guide to do a quick installation.
