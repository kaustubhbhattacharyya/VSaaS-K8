# VSaaS RCS Handler Helm Chart

This repository contains a Helm chart for deploying the VSaaS RCS Handler application on Kubernetes. The chart includes all necessary components including deployment, service, ingress, configmap, and secrets.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Configuration](#configuration)
- [Installation](#installation)
- [Management Script](#management-script)
- [Configurations](#configurations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Prerequisites

Before installing the chart, ensure you have the following:

- Kubernetes cluster (version >= 1.19)
- Helm (version >= 3.0.0)
- `kubectl` configured to communicate with your cluster
- Nginx Ingress Controller installed in the cluster
- Access to the vtpl/vrcshandler container registry

## Directory Structure

```plaintext
vsaas-rcshandler/
├── Chart.yaml
├── README.md
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   └── secret.yaml
└── scripts/
    └── hm-rcshandler.sh
```

## Configuration

### Values File (`values.yaml`)

The following table lists the configurable parameters of the RCS Handler chart and their default values:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `3` |
| `image.repository` | Image repository | `vtpl/vrcshandler` |
| `image.tag` | Image tag | `1.2.4b` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `nodeAffinity.hostname` | Node hostname for affinity | `masternode.vsaas.com` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `256Mi` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `service.type` | Service type | `ClusterIP` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.host` | Ingress hostname | `rcshandler.videonetics.com` |

## Installation

### Using Helm directly

```bash
# Add the repository (if applicable)
helm repo add vsaas-repo <repository-url>
helm repo update

# Install the chart
helm install vsaas-rcshandler ./vsaas-rcshandler -n vsaas-dev
```

### Using Management Script

The `hm-rcshandler.sh` script provides a convenient way to manage the Helm chart:

```bash
# Make the script executable
chmod +x hm-rcshandler.sh

# Install
./hm-rcshandler.sh install

# Upgrade
./hm-rcshandler.sh upgrade

# Uninstall
./hm-rcshandler.sh uninstall
```

## Management Script

The `hm-rcshandler.sh` script supports the following commands:

| Command | Description | Example |
|---------|-------------|---------|
| `install` | Install the chart | `./hm-rcshandler.sh install` |
| `uninstall` | Uninstall the release | `./hm-rcshandler.sh uninstall` |
| `upgrade` | Upgrade the release | `./hm-rcshandler.sh upgrade` |
| `rollback` | Rollback to previous version | `./hm-rcshandler.sh rollback -v 1` |
| `status` | Check release status | `./hm-rcshandler.sh status` |
| `template` | View rendered templates | `./hm-rcshandler.sh template` |
| `lint` | Lint the chart | `./hm-rcshandler.sh lint` |
| `list` | List all releases | `./hm-rcshandler.sh list` |

### Script Options

| Option | Description | Example |
|--------|-------------|---------|
| `-n, --namespace` | Specify namespace | `-n custom-namespace` |
| `-f, --values` | Specify values file | `-f custom-values.yaml` |
| `-v, --version` | Specify version for rollback | `-v 1` |

## Volume Configurations

The chart supports the following volume mounts:

1. VTPL Configuration Volume:
   - Host Path: `/home/vadmin/Kubernetes/soterix_vsaas_master/master/vtpl_cnf`
   - Mount Path: `/root/workfiles/vtpl_cnf`

2. Logs Volume:
   - Host Path: `/root/workfiles/VSaaSMasterServer/logs`
   - Mount Path: `/root/workfiles/VRCSHandler/logs`

3. System Volumes:
   - Timezone: `/etc/timezone`
   - Localtime: `/etc/localtime`

## Troubleshooting

Common issues and solutions:

1. **Pod Scheduling Issues**
   ```bash
   # Check node affinity
   kubectl get nodes --show-labels
   # Verify pod status
   kubectl describe pod -n vsaas-dev -l app=vsaas-rcshandler
   ```

2. **Service Connection Issues**
   ```bash
   # Check service endpoints
   kubectl get endpoints -n vsaas-dev vsaas-rcshandler-svc
   ```

3. **Ingress Issues**
   ```bash
   # Check ingress status
   kubectl describe ingress -n vsaas-dev vsaas-rcshandler-ingress
   ```

## Security Considerations

1. Secrets Management:
   - Database passwords are stored in Kubernetes secrets
   - Sensitive configurations are managed through ConfigMaps
   - Use appropriate RBAC permissions

2. Network Policies:
   - Configure appropriate network policies for the namespace
   - Restrict access to required services only

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request