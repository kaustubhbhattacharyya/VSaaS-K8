# VSaaS MongoDB Helm Chart Documentation

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [MongoDB Controls](#mongodb-controls)
7. [Troubleshooting](#troubleshooting)
8. [Maintenance](#maintenance)

## Overview
This Helm chart deploys MongoDB with custom VMongo data initialization for VSaaS environment. It includes automatic data restoration, initialization scripts, and proper configuration of MongoDB.

## Prerequisites

### Required Components
- Kubernetes cluster (v1.16+)
- Helm v3
- kubectl configured
- sshpass installed
- Storage class support for local persistent volumes

### Directory Structure
```
vsaas-mongodb/
├── Chart.yaml                 # Chart metadata
├── values.yaml               # Default configuration values
├── scripts/                  # Helper scripts
│   └── hm-vsaas-mongodb.sh  # Installation script
├── templates/                # Helm templates
│   ├── _helpers.tpl         # Template helpers
│   ├── configmap.yaml       # MongoDB configuration
│   ├── secret.yaml          # MongoDB credentials
│   ├── pv.yaml              # Persistent Volume
│   ├── pvc.yaml            # Persistent Volume Claim
│   ├── service.yaml        # MongoDB service
│   └── statefulset.yaml    # MongoDB StatefulSet
└── VMongo/                  # VMongo data directory
    ├── file.js             # Initialization script
    └── dump/               # MongoDB dump files
```

## Installation

### Environment Setup
```bash
# Set SSH password for worker node access
export SSH_PASSWORD="your_password"
```

### Automated Installation
```bash
./scripts/hm-vsaas-mongodb.sh install \
  --chart-path ./vsaas-mongodb \
  --vmongo-path ./vsaas-mongodb/VMongo
```

### Manual Installation
```bash
# Create namespace
kubectl create namespace vsaas-dev

# Install chart
helm install vsaas-mongodb . -n vsaas-dev
```

## Configuration

### values.yaml
```yaml
namespace: vsaas-dev
mongodb:
  image: mongo:5.0
  imagePullPolicy: Always
  storage:
    size: 10Gi
    path: /data/mongodb
  auth:
    username: root
    password: root@central1234
  nodeSelector:
    hostname: vsaas-workernode-3

service:
  port: 27017
  targetPort: 27017
  nodePort: 30017
```

## Usage

### Accessing MongoDB

1. Pod Access:
```bash
kubectl exec -it vsaas-mongodb-0 -n vsaas-dev -- mongosh \
  --username root \
  --password root@central1234
```

2. NodePort Access:
```bash
# Get node IP and port
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc -n vsaas-dev vsaas-mongodb -o jsonpath='{.spec.ports[0].nodePort}')

# Connect using mongosh
mongosh --host $NODE_IP --port $NODE_PORT \
  --username root \
  --password root@central1234
```

3. Connection String:
```bash
mongosh "mongodb://root:root@central1234@$NODE_IP:$NODE_PORT/admin?authSource=admin"
```

## MongoDB Controls

### Basic Commands
```javascript
// Database Operations
show dbs                     // List databases
use centralpro              // Switch database
show collections            // List collections
db.stats()                  // Database statistics

// Collection Operations
db.collection.find()        // Find all documents
db.collection.count()       // Count documents
db.collection.find().pretty() // Pretty print results

// Aggregation
db.collection.aggregate([
  { $match: { field: "value" } },
  { $group: { _id: "$field" } }
])

// Export/Import
mongoexport --collection=mycollection --db=mydb --out=data.json
mongoimport --collection=mycollection --db=mydb --file=data.json

// Backup/Restore
mongodump --out=/backup
mongorestore /backup
```

### Advanced Queries
```javascript
// Complex Find Operations
db.collection.find({
  field1: "value1",
  field2: { $gt: 100 }
})

// Sort Operations
db.collection.find().sort({ field: 1 })

// Pagination
db.collection.find().limit(10)
db.collection.find().skip(10)

// Counting with Conditions
db.collection.countDocuments({ field: "value" })

// Index Operations
db.collection.createIndex({ field: 1 })
db.collection.getIndexes()

// Collection Statistics
db.collection.stats()
```

## Troubleshooting

### Common Issues

1. Pod Issues:
```bash
# Check pod status
kubectl get pods -n vsaas-dev
kubectl describe pod vsaas-mongodb-0 -n vsaas-dev
kubectl logs vsaas-mongodb-0 -n vsaas-dev
```

2. Storage Issues:
```bash
# Check storage
kubectl get pv,pvc -n vsaas-dev
kubectl describe pv <pv-name>
```

3. Connection Issues:
```bash
# Check service
kubectl get svc -n vsaas-dev
kubectl describe svc vsaas-mongodb -n vsaas-dev
```

### Debug Commands
```javascript
// MongoDB Status Checks
db.serverStatus()
db.stats()
db.runCommand({connectionStatus: 1})
```

## Maintenance

### Backup and Restore
```bash
# Create Backup
kubectl exec -it vsaas-mongodb-0 -n vsaas-dev -- \
  mongodump --username root --password root@central1234 --out /data/backup

# Restore from Backup
kubectl exec -it vsaas-mongodb-0 -n vsaas-dev -- \
  mongorestore --username root --password root@central1234 /data/backup
```

### Upgrading MongoDB
```bash
helm upgrade vsaas-mongodb . -n vsaas-dev \
  --set mongodb.image=mongo:5.1
```

### Scaling
```bash
kubectl scale statefulset vsaas-mongodb -n vsaas-dev --replicas=3
```

### Uninstallation
```bash
# Using script
./scripts/hm-vsaas-mongodb.sh uninstall

# Manual uninstall
helm uninstall vsaas-mongodb -n vsaas-dev
kubectl delete pvc -n vsaas-dev vsaas-mongodb-pvc
kubectl delete pv vsaas-mongodb-pv
```

## Best Practices

### Security
1. Change default passwords
2. Use secrets for sensitive data
3. Configure network policies
4. Enable authentication and authorization
5. Use secure connections (TLS)
6. Regular security updates

### Performance
1. Use appropriate indexes
2. Monitor resource usage
3. Regular maintenance
4. Backup strategy
5. Resource limits

### Monitoring
1. Resource usage
2. Connection counts
3. Query performance
4. Storage usage
5. Backup status

### Data Management
1. Regular backups
2. Data validation
3. Index maintenance
4. Storage monitoring
5. Archival strategy

## MongoDB Commands Quick Reference

### Collection Management
```javascript
// Create collection
db.createCollection("name")

// Drop collection
db.collection.drop()

// Rename collection
db.collection.renameCollection("newName")

// Compact collection
db.runCommand({ compact: "collection" })
```

### Document Operations
```javascript
// Insert document
db.collection.insertOne({ field: "value" })

// Update document
db.collection.updateOne(
  { field: "value" },
  { $set: { newField: "newValue" } }
)

// Delete document
db.collection.deleteOne({ field: "value" })

// Bulk operations
db.collection.bulkWrite([
  { insertOne: { document: { field: "value" } } },
  { updateOne: { 
      filter: { field: "value" },
      update: { $set: { field: "newValue" } }
    }
  }
])
```

### Index Operations
```javascript
// Create index
db.collection.createIndex({ field: 1 })

// List indexes
db.collection.getIndexes()

// Drop index
db.collection.dropIndex("index_name")

// Reindex collection
db.collection.reIndex()
```

### Administration
```javascript
// User management
db.createUser({
  user: "username",
  pwd: "password",
  roles: ["readWrite"]
})

// Role management
db.grantRolesToUser("username", ["role"])

// Database stats
db.stats()

// Collection stats
db.collection.stats()
```