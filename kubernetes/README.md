# Ansible Playbooks for Managing K3s Cluster

This repository contains Ansible playbooks to manage a K3s Kubernetes cluster. Below is a detailed description of each playbook included.

## `deploy-k3s.yaml`

This playbook deploys K3s Kubernetes cluster on specified nodes. It installs K3s with server roles on the designated nodes and sets up the cluster.

### Usage

ansible-playbook deploy-k3s.yaml -i hosts.ini

Replace `hosts.ini` with your actual inventory file containing the list of nodes where K3s will be deployed.

### Tasks

- Installs K3s with server role on designated nodes.
- Configures K3s to use a specific server URL and token.

---

## `remove-k3s.yaml`

This playbook uninstalls K3s Kubernetes cluster from the nodes. It ensures that K3s is cleanly removed from each node specified in the inventory.

### Usage

ansible-playbook remove-k3s.yaml -i hosts.ini

Replace `hosts.ini` with your actual inventory file containing the list of nodes from which K3s should be removed.

### Tasks

- Runs the K3s uninstall script on each node.
- Handles cleanup and removal of K3s components.

---

## `update-hosts.yaml`

This playbook updates the `/etc/hosts` file on all nodes and sets their hostnames according to the inventory. It ensures that each node has the correct IP address and hostname mapping.

### Usage

ansible-playbook update-hosts.yaml -i hosts.ini

Replace `hosts.ini` with your actual inventory file containing the list of nodes to update `/etc/hosts` for.

### Tasks

- Sets the hostname of each node to match its inventory name.
- Updates the `/etc/hosts` file to ensure correct IP address to hostname mapping.

