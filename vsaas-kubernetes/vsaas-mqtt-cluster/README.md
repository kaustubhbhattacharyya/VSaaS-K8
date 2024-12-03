# VSAAS MQTT Helm Chart

This repository contains a Helm chart for deploying RabbitMQ with MQTT support in Kubernetes, along with a management script for easy deployment operations.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Configuration](#configuration)
- [Installation](#installation)
- [Management Script](#management-script)
- [Chart Values](#chart-values)
- [Services Exposed](#services-exposed)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- kubectl CLI tool
- Access to a Kubernetes cluster
- Nginx Ingress Controller (for ingress support)

## Directory Structure

```plaintext
vsaas-mqtt/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml     # Environment specific values
├── values-staging.yaml
├── values-prod.yaml
├── templates/
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── _helpers.tpl
├── hm-mqtt.sh         # Management script
└── README.md
```

## Configuration

### Basic Configuration (values.yaml)

```yaml
image:
  repository: rabbitmq
  tag: 3.8-management
  pullPolicy: IfNotPresent

replicaCount: 1

rabbitmq:
  username: guest
  password: guest
  adminUsername: admin
  adminPassword: admin

ingress:
  enabled: true
  className: nginx
  host: soterix-rabbitmq.portal.com
  path: /
  pathType: Prefix
```

### Environment-Specific Configuration

Create environment-specific values files (`values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`) to override default values for different environments.

## Installation

### Manual Installation

```bash
# Install the chart
helm install vsaas-mqtt ./vsaas-mqtt -n vsaas-dev

# Upgrade the chart
helm upgrade vsaas-mqtt ./vsaas-mqtt -n vsaas-dev

# Uninstall the chart
helm uninstall vsaas-mqtt -n vsaas-dev
```

### Using Management Script

The `hm-mqtt.sh` script provides a simplified interface for managing the Helm chart deployment.

```bash
# Make script executable
chmod +x hm-mqtt.sh

# Install in dev environment
./hm-mqtt.sh install dev 1.0.0

# Upgrade in staging
./hm-mqtt.sh upgrade staging 1.1.0

# Check status
./hm-mqtt.sh status prod

# Uninstall
./hm-mqtt.sh uninstall dev
```

### Script Operations

| Operation  | Description                     | Example                           |
|------------|---------------------------------|-----------------------------------|
| install    | Install the chart              | `./hm-mqtt.sh install dev 1.0.0`  |
| upgrade    | Upgrade existing deployment     | `./hm-mqtt.sh upgrade dev 1.0.1`  |
| uninstall  | Remove deployment              | `./hm-mqtt.sh uninstall dev`      |
| rollback   | Rollback to previous version   | `./hm-mqtt.sh rollback dev`       |
| status     | Check deployment status        | `./hm-mqtt.sh status dev`         |
| lint       | Lint the Helm chart           | `./hm-mqtt.sh lint dev`           |

## Services Exposed

| Service    | Port  | Description                |
|------------|-------|----------------------------|
| MQTT       | 1883  | MQTT protocol             |
| AMQP       | 5672  | AMQP protocol             |
| HTTP       | 15672 | Management interface      |
| Web MQTT   | 15675 | MQTT over WebSocket       |

## Security Considerations

1. **Credentials:**
   - Default credentials are provided in `values.yaml`
   - Override these in environment-specific values files
   - Use Kubernetes secrets for production deployments

2. **Network Access:**
   - The service exposes multiple ports
   - Configure network policies as needed
   - Use TLS for production deployments

3. **RBAC:**
   - The chart includes basic RBAC resources
   - Customize based on your security requirements

## Troubleshooting

### Common Issues

1. **Pod not starting:**
   ```bash
   kubectl describe pod -n vsaas-dev <pod-name>
   kubectl logs -n vsaas-dev <pod-name>
   ```

2. **Service not accessible:**
   ```bash
   kubectl get svc -n vsaas-dev
   kubectl get endpoints -n vsaas-dev
   ```

3. **Ingress issues:**
   ```bash
   kubectl describe ingress -n vsaas-dev
   kubectl get events -n vsaas-dev
   ```

### Health Check Commands

```bash
# Check pod status
kubectl get pods -n vsaas-dev -l app=vsaas-mqtt

# Check service status
kubectl get svc -n vsaas-dev vsaas-mqtt

# Check logs
kubectl logs -n vsaas-dev -l app=vsaas-mqtt
```

## Chart Values

| Parameter                  | Description                           | Default               |
|---------------------------|---------------------------------------|-----------------------|
| `image.repository`        | RabbitMQ image repository            | `rabbitmq`           |
| `image.tag`              | RabbitMQ image tag                   | `3.8-management`     |
| `image.pullPolicy`       | Image pull policy                    | `IfNotPresent`       |
| `replicaCount`           | Number of replicas                   | `1`                  |
| `rabbitmq.username`      | Default RabbitMQ user               | `guest`              |
| `rabbitmq.password`      | Default RabbitMQ password           | `guest`              |
| `rabbitmq.adminUsername` | Admin username                       | `admin`              |
| `rabbitmq.adminPassword` | Admin password                       | `admin`              |
| `ingress.enabled`        | Enable ingress                       | `true`               |
| `ingress.className`      | Ingress class name                  | `nginx`              |
| `ingress.host`          | Ingress hostname                    | `rabbitmq.local`     |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request
