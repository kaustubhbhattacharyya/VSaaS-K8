# MongoDB Data Import Instructions

This document outlines the steps required to import data into a MongoDB container pod.

## Prerequisites

- Kubernetes cluster with MongoDB deployment running
- `kubectl` CLI tool installed and configured
- MongoDB tools (`mongosh` and `mongorestore`) installed locally
- Access to MongoDB pod with proper credentials

## Steps

1. **Wait for MongoDB Pod Readiness**
   - Ensure the MongoDB container pod is fully running and ready
   - You can check the pod status using:
     ```bash
     kubectl get pods -n mongodb
     ```
   - Wait until the status shows `Running` and all containers are ready

2. **Copy Data Files to Pod**
   ```bash
   kubectl cp ./VMongo mongodb-deployment-5cf56c9947-5759c:/data/VMongo -n mongodb
   ```
   This command copies the local `VMongo` directory to the `/data/VMongo` path inside the MongoDB pod.

3. **Execute MongoDB Script**
   ```bash
   mongosh < VMongo/file.js > /dev/null
   ```
   This step executes the JavaScript file containing MongoDB commands.

4. **Restore Database Dump**
   ```bash
   /usr/bin/mongorestore -u root -p root@central1234 VMongo/dump/ > /dev/null
   ```
   This command restores the database from the dump files using the provided credentials.

## Notes

- Replace `mongodb-deployment-5cf56c9947-5759c` with your actual pod name
- Ensure proper permissions are set for executing these commands
- The `> /dev/null` redirects output to null device (suppresses output)
- Default credentials used: 
  - Username: root
  - Password: root@central1234

## Troubleshooting

If you encounter any issues:
1. Verify the pod is running and accessible
2. Check if the VMongo directory exists locally
3. Ensure you have the correct namespace (-n mongodb)
4. Verify MongoDB credentials are correct