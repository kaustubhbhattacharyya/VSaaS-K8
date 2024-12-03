# VSaaS Admin Portal Helm Chart

This repository contains the Helm chart for deploying the VSaaS Admin Portal application to Kubernetes clusters. The chart includes deployments, services, ingress configurations, and necessary environment variables.

## Prerequisites

- Kubernetes 1.16+
- Helm 3.0+
- kubectl configured to connect to your cluster
- NGINX Ingress Controller installed in the cluster

## Directory Structure

```
vsaas-adminportal/
├── Chart.yaml             # Chart metadata
├── values.yaml           # Default configuration values
├── README.md            # This documentation
├── hm-adminportal.sh    # Operations script
└── templates/
    ├── deployment.yaml   # Application deployment
    ├── service.yaml      # Service definition
    ├── ingress.yaml      # Ingress configuration
    ├── configmap.yaml    # Environment variables
    └── _helpers.tpl      # Helper templates
```

## Configuration

The following table lists the configurable parameters in the `values.yaml` file:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `3` |
| `image.repository` | Container image repository | `vtpl/vsaasenterprise-k8` |
| `image.tag` | Container image tag | `1.2.2b` |
| `image.pullPolicy` | Image pull policy | `Always` |
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `23000` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.host` | Ingress hostname | `soterix.admin.portal.com` |
| `configMap.nodeEnv` | Node environment | `production` |
| `configMap.backendServiceHost` | Backend service host | `soterix-vsaas-master-api-svc.vsaas-master.svc.cluster.local` |
| `configMap.backendServicePort` | Backend service port | `8090` |

## Resource Requirements

Default resource limits:
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi
```

## Operations Script Usage (hm-adminportal.sh)

The `hm-adminportal.sh` script provides a command-line interface for managing the Helm chart deployments.

### Basic Commands

```bash
# Make script executable
chmod +x hm-adminportal.sh

# Display help
./hm-adminportal.sh -h

# Install the chart
./hm-adminportal.sh install

# Upgrade the deployment
./hm-adminportal.sh upgrade

# Uninstall the release
./hm-adminportal.sh uninstall
```

### Available Commands
- `install`: Install the Helm chart
- `uninstall`: Uninstall the Helm chart
- `upgrade`: Upgrade the Helm chart
- `rollback`: Rollback to previous release
- `status`: Check the status of the release
- `template`: Template the chart and display output
- `lint`: Lint the chart

### Script Options
```bash
Options:
  -n, --namespace NAMESPACE    Specify Kubernetes namespace (default: vsaas-dev)
  -r, --release RELEASE_NAME   Specify release name (default: vsaas-adminportal)
  -f, --values VALUES_FILE     Specify values file (default: values.yaml)
  -t, --timeout TIMEOUT        Specify timeout duration (default: 5m)
  -h, --help                   Display help message
```

### Examples

```bash
# Install with custom namespace
./hm-adminportal.sh -n custom-namespace install

# Upgrade with custom values file
./hm-adminportal.sh -f custom-values.yaml upgrade

# Check status in specific namespace
./hm-adminportal.sh -n vsaas-dev status

# Install with custom timeout
./hm-adminportal.sh -t 10m install
```

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd vsaas-adminportal
```

2. Modify the `values.yaml` file according to your environment:
```bash
vi values.yaml
```

3. Install the chart:
```bash
./hm-adminportal.sh install
```

## Upgrading

To upgrade the deployment with new configurations:

1. Update the values in `values.yaml` or create a new values file
2. Run the upgrade command:
```bash
./hm-adminportal.sh upgrade
# or with custom values file
./hm-adminportal.sh -f new-values.yaml upgrade
```

## Uninstallation

To remove the deployment:
```bash
./hm-adminportal.sh uninstall
```

## Troubleshooting

1. Check the status of the deployment:
```bash
./hm-adminportal.sh status
```

2. View the templated manifest:
```bash
./hm-adminportal.sh template
```

3. Validate the chart:
```bash
./hm-adminportal.sh lint
```

## Maintenance

### Backing Up Values
Always backup your `values.yaml` file before making changes:
```bash
cp values.yaml values.yaml.backup
```

### Version Control
Track changes to your configurations using version control:
```bash
git add values.yaml
git commit -m "Update configuration values"
```

## Security Considerations

1. The chart uses CORS configurations in the ingress. Review and adjust the CORS settings according to your security requirements.
2. Ensure proper network policies are in place for the backend service communication.
3. Review and adjust resource limits based on application requirements.
4. Consider implementing pod security policies.

## Support

For issues and support:
1. Check the logs of the deployed pods
2. Verify the configmap values
3. Ensure ingress controller is properly configured
4. Check the Kubernetes events in the namespace

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request