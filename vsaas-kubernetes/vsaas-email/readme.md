# VSaaS Email Service Helm Chart

This Helm chart deploys the VSaaS Email Service on a Kubernetes cluster. The service handles email operations including enterprise registration, password management, and clip sharing functionalities.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Installation](#installation)
- [Configuration](#configuration)
- [Management Script](#management-script)
- [Dependencies](#dependencies)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- kubectl configured to communicate with your cluster
- MongoDB instance accessible from the cluster
- Namespace where the service will be deployed

## Directory Structure

```
vsaas-email/
├── Chart.yaml             # Chart metadata
├── values.yaml           # Default configuration values
├── values-dev.yaml       # Development environment values
├── values-staging.yaml   # Staging environment values
├── values-prod.yaml      # Production environment values
├── README.md            # This file
├── hm-email.sh         # Helm operations management script
└── templates/
    ├── deployment.yaml  # Main application deployment
    ├── service.yaml    # Kubernetes service definition
    ├── ingress.yaml    # Ingress configuration
    ├── configmap.yaml  # Application configuration
    └── secret.yaml     # Sensitive data storage
```

## Installation

### Using the Management Script

The provided `hm-email.sh` script handles all Helm operations:

```bash
# Make the script executable
chmod +x hm-email.sh

# Install in development environment
./hm-email.sh install dev

# Install in staging with specific version
./hm-email.sh install staging 1.0.0

# Install in production
./hm-email.sh install prod
```

### Manual Installation

```bash
# Add repository (if hosted in a repository)
helm repo add vsaas-repo https://your-helm-repo.com
helm repo update

# Install the chart
helm install vsaas-email ./vsaas-email \
  --namespace vsaas-dev \
  --values values-dev.yaml
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `3` |
| `image.repository` | Docker image repository | `vtpl/vemailservices` |
| `image.tag` | Docker image tag | `1.2.4b` |
| `service.port` | Service port | `8095` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `mongodb.auth.username` | MongoDB username | `root` |
| `probes.enabled` | Enable liveness/readiness probes | `false` |

### Environment-Specific Configuration

Create environment-specific values files:

```yaml
# values-dev.yaml example
environment: development
resources:
  requests:
    memory: "512Mi"
  limits:
    memory: "1Gi"

# values-prod.yaml example
environment: production
replicaCount: 5
resources:
  requests:
    memory: "1Gi"
  limits:
    memory: "2Gi"
```

## Management Script

The `hm-email.sh` script provides the following operations:

```bash
Usage: ./hm-email.sh [operation] [environment] [version]

Operations:
  install     - Install the Helm chart
  uninstall   - Uninstall the Helm release
  upgrade     - Upgrade the Helm release
  rollback    - Rollback to the previous release
  status      - Check the status of the release
  lint        - Lint the Helm chart
  template    - Template the chart (dry-run)

Environments:
  dev        - Development environment
  staging    - Staging environment
  prod       - Production environment

Version: Optional - defaults to 0.1.0
```

## Dependencies

- MongoDB: Requires a running MongoDB instance
- Kubernetes Ingress Controller: Required for ingress functionality
- Metrics Server: Optional, required for HPA if implemented

## Monitoring & Health Checks

### Probes
The service includes optional liveness and readiness probes:
```yaml
probes:
  enabled: true
  liveness:
    path: /v-mail-sms/actuator/health
    initialDelaySeconds: 60
  readiness:
    path: /v-mail-sms/actuator/health
    initialDelaySeconds: 30
```

### Metrics

Enable metrics collection by configuring appropriate annotations:
```yaml
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8095"
  prometheus.io/path: "/v-mail-sms/actuator/prometheus"
```

## Troubleshooting

### Common Issues

1. **Pod Startup Failure**
   ```bash
   kubectl describe pod -n vsaas-dev vsaas-email-[pod-id]
   kubectl logs -n vsaas-dev vsaas-email-[pod-id]
   ```

2. **MongoDB Connection Issues**
   - Verify MongoDB service is accessible
   - Check MongoDB credentials in secrets
   - Validate MongoDB connection string

3. **Resource Constraints**
   ```bash
   kubectl top pods -n vsaas-dev
   ```

### Debug Mode

Enable debug logging by setting the appropriate environment variable:
```yaml
env:
  - name: LOG_LEVEL
    value: "DEBUG"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Submit a pull request