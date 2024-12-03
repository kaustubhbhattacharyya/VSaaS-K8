# VSaaS User Portal Helm Chart

A Helm chart for deploying the VSaaS User Portal application on Kubernetes.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Chart Components](#chart-components)
- [Installation](#installation)
- [Configuration](#configuration)
- [Management Script](#management-script)
- [Directory Structure](#directory-structure)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Overview

This Helm chart deploys a VSaaS User Portal application with the following features:
- Scalable deployment with configurable replicas
- Ingress configuration for external access
- ConfigMap for environment variables
- Persistent storage configuration
- Service configuration for internal communication

## Prerequisites

- Kubernetes cluster 1.19+
- Helm 3.0+
- kubectl configured to communicate with your cluster
- NGINX Ingress Controller installed in the cluster

## Chart Components

The chart deploys the following Kubernetes resources:
- Namespace
- Deployment
- Service
- Ingress
- ConfigMap
- Persistent Volume (optional)

## Installation

### Using the Management Script

1. Clone the repository:
```bash
git clone <repository-url>
cd vsaas-userportal
```

2. Make the management script executable:
```bash
chmod +x helm-manage.sh
```

3. Install the chart:
```bash
./helm-manage.sh install
```

### Manual Installation

1. Customize the values in `values.yaml`

2. Install the chart:
```bash
helm install vsaas-userportal ./vsaas-userportal -n vsaas-dev
```

## Configuration

### values.yaml Options

```yaml
# Deployment configuration
deployment:
  replicas: 3
  image:
    repository: vtpl/vsaasclientportal
    tag: 1.2.4b
    pullPolicy: IfNotPresent
  containerPort: 3010
  
# Service configuration
service:
  type: ClusterIP
  port: 3010
  targetPort: 3010

# Ingress configuration
ingress:
  enabled: true
  className: nginx
  host: 10.3.0.2

# ConfigMap data
configMap:
  namespace: vsaas-web
  data:
    NODE_ENV: "production"
    HTTP_SERVER_IP: "soterix-vsaas-master-api-svc.vsaas-master.svc.cluster.local"
    HTTP_SERVER_PORT: "8090"
    # ... additional environment variables
```

### Important Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `deployment.replicas` | Number of pod replicas | `3` |
| `deployment.image.tag` | Container image tag | `1.2.4b` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.host` | Ingress host | `10.3.0.2` |

## Management Script

The `helm-manage.sh` script provides the following commands:

```bash
# Install the application
./helm-manage.sh install

# Upgrade existing installation
./helm-manage.sh upgrade

# Remove installation and cleanup
./helm-manage.sh cleanup

# Check deployment status
./helm-manage.sh status

# Validate chart
./helm-manage.sh validate
```

### Script Features
- Automated installation and cleanup
- Prerequisites checking
- Namespace management
- Deployment validation
- Resource cleanup
- Colored output for better visibility

## Directory Structure

```
vsaas-userportal/
├── Chart.yaml
├── values.yaml
├── README.md
├── helm-manage.sh
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── configmap.yaml
```

## Upgrading

### Using Management Script
```bash
./helm-manage.sh upgrade
```

### Manual Upgrade
```bash
helm upgrade vsaas-userportal ./vsaas-userportal -n vsaas-dev
```

## Troubleshooting

### Common Issues

1. **Pod not starting**
   ```bash
   kubectl describe pod -n vsaas-dev
   kubectl logs -n vsaas-dev <pod-name>
   ```

2. **Service not accessible**
   ```bash
   kubectl get svc -n vsaas-dev
   kubectl describe svc vsaas-userportal-service -n vsaas-dev
   ```

3. **Ingress not working**
   ```bash
   kubectl get ingress -n vsaas-dev
   kubectl describe ingress vsaas-userportal-ingress -n vsaas-dev
   ```

### Validation
```bash
# Validate chart
./helm-manage.sh validate

# Check deployment status
./helm-manage.sh status
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a pull request

### Development Guidelines

- Follow Helm best practices
- Update documentation for any new features
- Add appropriate labels to pull requests
- Ensure all tests pass before submitting