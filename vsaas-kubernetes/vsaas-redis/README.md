# Redis Helm Chart

This Helm chart deploys a Redis cluster on a Kubernetes cluster.

## Prerequisites

- Kubernetes cluster
- Helm (version 3+)
- `vsaas-dev` namespace created in the Kubernetes cluster

## Chart Details

- Chart Name: `vsaas-redis`
- Chart Version: `0.1.0`
- App Version: `1.0.0`

## Installing the Chart

To install the Redis Helm chart, follow these steps:

1. Clone the repository containing the Helm chart:

   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. Make sure the `vsaas-dev` namespace exists in your Kubernetes cluster. If not, create it:

   ```bash
   kubectl create namespace vsaas-dev
   ```

3. Run the `hm-vsaas-redis.sh` shell script with the `install` command:

   ```bash
   ./hm-vsaas-redis.sh install
   ```

   This script will install the Redis Helm chart in the `vsaas-dev` namespace with the release name `vsaas-redis`.

## Upgrading the Chart

To upgrade the Redis Helm chart, run the following command:

```bash
./hm-vsaas-redis.sh upgrade
```

This will upgrade the existing `vsaas-redis` release in the `vsaas-dev` namespace.

## Uninstalling the Chart

To uninstall the Redis Helm chart, run the following command:

```bash
./hm-vsaas-redis.sh uninstall
```

This will uninstall the `vsaas-redis` release from the `vsaas-dev` namespace.

## Configuration

The following table lists the configurable parameters of the Redis Helm chart and their default values.

| Parameter                      | Description                                           | Default                   |
| ------------------------------ | ----------------------------------------------------- | ------------------------- |
| `namespace`                    | Namespace to deploy the Redis cluster                 | `vsaas-dev`               |
| `redis.image`                  | Redis container image                                 | `redis`                   |
| `redis.replicas`               | Number of Redis replicas                              | `3`                       |
| `redis.password`               | Password for Redis authentication                     | `root`                    |
| `redis.storage.size`           | Size of the Redis persistent volume                   | `1Gi`                     |
| `redis.storage.storageClassName` | Storage class name for Redis persistent volume       | `standard-wait-consumer` |
| `redis.storage.hostPath`       | Host path for Redis persistent volume                 | `/mnt/data`               |
| `redis.nodeSelector.hostname`  | Node selector for Redis pods                          | `vsaas-workernode-2`      |
| `service.port`                 | Port for the Redis service                            | `6379`                    |
| `service.targetPort`           | Target port for the Redis service                     | `6379`                    |

To customize the chart, modify the `values.yaml` file with the desired configuration.

## Shell Script

The `hm-vsaas-redis.sh` shell script provides the following commands:

- `install`: Installs the Redis Helm chart.
- `upgrade`: Upgrades the Redis Helm chart.
- `uninstall`: Uninstalls the Redis Helm chart.
- `status`: Displays the status of the Redis Helm release.
- `help`: Displays the help information.

The script uses the following variables:

- `NAMESPACE`: The namespace to deploy the Redis cluster (default: `vsaas-dev`).
- `CHART_FOLDER`: The folder containing the Redis Helm chart (default: `vsaas-redis`).
- `RELEASE_NAME`: The release name for the Redis Helm chart (default: `vsaas-redis`).

The script also includes a logging function (`log_message`) to log messages with timestamps.