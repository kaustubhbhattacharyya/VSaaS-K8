#!/bin/bash

readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly LOG_FILE="${SCRIPT_DIR}/mongodb-install.log"

NAMESPACE="vsaas-dev"
RELEASE_NAME="vsaas-mongodb"
CHART_PATH="./vsaas-mongodb"
VMONGO_PATH="./vsaas-mongodb/VMongo"
WORKER_NODE="10.3.0.5"
STORAGE_PATH="/data/mongodb"
TIMEOUT=300
SSH_PASSWORD="${SSH_PASSWORD:-Videonetics##156}"  

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] $1${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
    exit 1
}

show_usage() {
    echo "Usage: $0 install --chart-path <chart-path> --vmongo-path <vmongo-path>"
    echo
    echo "Options:"
    echo "  --chart-path   Path to the Helm chart directory"
    echo "  --vmongo-path  Path to the VMongo directory"
    echo
    echo "Environment variables:"
    echo "  SSH_PASSWORD   SSH password for worker node (default: Videonetics##156)"
    echo "  NAMESPACE      Kubernetes namespace (default: vsaas-dev)"
    echo
    echo "Example:"
    echo "  SSH_PASSWORD='your_password' $0 install --chart-path ./vsaas-mongodb --vmongo-path ./vsaas-mongodb/VMongo"
}

parse_args() {
    if [ $# -lt 1 ]; then
        show_usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            install)
                ACTION="install"
                shift
                ;;
            --chart-path)
                CHART_PATH="$2"
                shift 2
                ;;
            --vmongo-path)
                VMONGO_PATH="$2"
                shift 2
                ;;
            *)
                error "Unknown parameter: $1"
                ;;
        esac
    done

    if [ -z "$CHART_PATH" ] || [ -z "$VMONGO_PATH" ]; then
        error "Both --chart-path and --vmongo-path are required"
    fi
}

manual_cleanup() {
    log "Performing manual cleanup..."
    
    # Force delete namespace resources
    kubectl delete statefulset,deployment,svc,pod,pvc -n vsaas-dev -l app.kubernetes.io/instance=vsaas-mongodb --force --grace-period=0
    
    # Remove helm history
    rm -rf ~/.helm/repository/local/vsaas-mongodb*
    
    # Delete helm release history from secret
    kubectl delete secret -n vsaas-dev -l name=vsaas-mongodb
    kubectl delete secret -n vsaas-dev -l owner=helm
    
    log "Manual cleanup completed"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    local required_commands=("kubectl" "helm" "sshpass")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' not found. Please install $cmd"
        fi
    done

    if [ ! -d "$CHART_PATH" ]; then
        error "Chart directory not found at $CHART_PATH"
    fi

    if [ ! -d "$VMONGO_PATH" ]; then
        error "VMongo directory not found at $VMONGO_PATH"
    fi

    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi

    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        error "Namespace $NAMESPACE does not exist"
    fi

    log "Prerequisites check completed"
}

prepare_worker_node() {
    log "Preparing worker node..."
    
    if ! sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no root@$WORKER_NODE "mkdir -p $STORAGE_PATH && chmod -R 777 $STORAGE_PATH"; then
        error "Failed to create storage directory on worker node"
    fi

    log "Worker node preparation completed"
}

# Function to install MongoDB
install_mongodb() {
    log "Installing MongoDB using Helm..."
    
    # First, ensure namespace exists with proper labels
    kubectl create namespace $NAMESPACE 2>/dev/null || true
    
    # Label the namespace for Helm
    kubectl label namespace $NAMESPACE \
        app.kubernetes.io/managed-by=Helm \
        helm.sh/chart=mongodb-0.1.0 \
        --overwrite

    # Annotate the namespace
    kubectl annotate namespace $NAMESPACE \
        meta.helm.sh/release-name=$RELEASE_NAME \
        meta.helm.sh/release-namespace=$NAMESPACE \
        --overwrite
    
    # Install/upgrade Helm chart
    if ! helm install $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --wait \
        --timeout ${TIMEOUT}s; then
        error "Failed to install MongoDB"
    fi
    
    log "MongoDB installation completed"
}

# Function to wait for pod readiness
wait_for_pod() {
    local counter=0
    local max_attempts=60
    local pod_name=""
    
    while [ $counter -lt $max_attempts ]; do
        pod_name=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vsaas-mongodb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$pod_name" ]; then
            if kubectl wait --for=condition=ready pod/$pod_name -n $NAMESPACE --timeout=10s &> /dev/null; then
                # Just return the pod name, nothing else
                echo "$pod_name"
                return 0
            fi
        fi
        sleep 5
        ((counter++))
    done
    
    return 1
}

copy_vmongo_data() {
    local pod_name="$1"
    
    log "Copying VMongo data to pod ${pod_name}..."
    
    if ! kubectl exec -n "$NAMESPACE" "$pod_name" -- mkdir -p /data/vmongo; then
        error "Failed to create vmongo directory in pod"
    fi
    
    if ! kubectl cp "${VMONGO_PATH}/." "${NAMESPACE}/${pod_name}:/data/vmongo"; then
        error "Failed to copy VMongo data"
    fi
    
    log "Verifying copied files..."
    if ! kubectl exec -n "$NAMESPACE" "$pod_name" -- ls -la /data/vmongo; then
        error "Failed to verify copied files"
    fi
}

initialize_mongodb() {
    local pod_name=$1
    log "Initializing MongoDB..."
    
    kubectl exec -n $NAMESPACE $pod_name -- bash -c "
        set -e
        
        # Set mongo command
        if command -v mongosh &> /dev/null; then
            MONGO_CMD=mongosh
        else
            MONGO_CMD=mongo
        fi
        
        echo 'Verifying VMongo data...'
        ls -la /data/vmongo
        
        if [ -f '/data/vmongo/file.js' ]; then
            echo 'Running initialization script...'
            \$MONGO_CMD --username \$MONGO_INITDB_ROOT_USERNAME \
                    --password \$MONGO_INITDB_ROOT_PASSWORD \
                    < /data/vmongo/file.js || {
                echo 'Failed to run initialization script'
                exit 1
            }
            echo 'Initialization script completed'
        else
            echo 'No initialization script found at /data/vmongo/file.js'
        fi
        
        if [ -d '/data/vmongo/dump' ]; then
            echo 'Restoring database...'
            mongorestore --username \$MONGO_INITDB_ROOT_USERNAME \
                        --password \$MONGO_INITDB_ROOT_PASSWORD \
                        --verbose \
                        /data/vmongo/dump/ || {
                echo 'Failed to restore database'
                exit 1
            }
            echo 'Database restore completed'
        else
            echo 'No dump directory found at /data/vmongo/dump'
        fi
    " || error "Failed to initialize MongoDB"
    
    log "MongoDB initialization completed"
}

verify_vmongo_directory() {
    log "Verifying VMongo directory contents..."
    
    if [ ! -d "$VMONGO_PATH" ]; then
        error "VMongo directory not found at $VMONGO_PATH"
    fi
    
    if [ ! -f "$VMONGO_PATH/file.js" ]; then
        warn "file.js not found in VMongo directory"
    fi
    
    if [ ! -d "$VMONGO_PATH/dump" ]; then
        warn "dump directory not found in VMongo directory"
    fi
    
    log "VMongo directory contents:"
    ls -la "$VMONGO_PATH"
    
    log "VMongo directory verification completed"
}

verify_mongodb() {
    local pod_name=$1
    log "Verifying MongoDB installation..."
    
    kubectl exec -n $NAMESPACE $pod_name -- bash -c '
        if command -v mongosh &> /dev/null; then
            MONGO_CMD=mongosh
        else
            MONGO_CMD=mongo
        fi
        
        $MONGO_CMD --username $MONGO_INITDB_ROOT_USERNAME \
                  --password $MONGO_INITDB_ROOT_PASSWORD \
                  --eval "db.adminCommand(\"ping\")"
    ' || error "MongoDB verification failed"
    
    log "MongoDB verification completed"
}

show_spinner() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${message} %c " "${spin:$i:1}"
        sleep .1
    done
    printf "\r${message} Complete\n"
}

print_connection_info() {
    log "MongoDB Connection Information:"
    local node_ip=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}")
    local node_port=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME -o jsonpath="{.spec.ports[0].nodePort}")
    
    echo -e "\nConnection String: mongodb://root:root@central1234@$node_ip:$node_port"
    echo -e "Namespace: $NAMESPACE"
    echo -e "Release: $RELEASE_NAME"
}

verify_installation() {
    local pod_name=$1
    
    log "Verifying installation..."
    
    # Check StatefulSet
    log "StatefulSet status:"
    kubectl get statefulset -n $NAMESPACE
    
    # Check PVC
    log "PVC status:"
    kubectl get pvc -n $NAMESPACE
    
    # Check ConfigMap
    log "ConfigMap status:"
    kubectl get configmap -n $NAMESPACE
    
    # Check Service
    log "Service status:"
    kubectl get svc -n $NAMESPACE
    
    # Check Pod details
    log "Pod details:"
    kubectl describe pod $pod_name -n $NAMESPACE
}

setup_storage_class() {
    log "Setting up StorageClass..."
    
    kubectl delete storageclass local-storage 2>/dev/null || true
    
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

    log "StorageClass setup completed"
}

# Update cleanup function to handle namespace properly
cleanup_resources() {
    log "Cleaning up existing resources..."
    
    # Remove failed helm release
    helm uninstall vsaas-mongodb -n vsaas-dev 2>/dev/null || true
    
    # Delete all resources with certain labels
    kubectl delete all -n vsaas-dev -l app.kubernetes.io/instance=vsaas-mongodb 2>/dev/null || true
    
    # Delete PVCs
    kubectl delete pvc -n vsaas-dev -l app.kubernetes.io/instance=vsaas-mongodb 2>/dev/null || true
    
    # Delete PVs
    kubectl delete pv -l app.kubernetes.io/instance=vsaas-mongodb 2>/dev/null || true
    
    # Delete ConfigMaps
    kubectl delete configmap -n vsaas-dev -l app.kubernetes.io/instance=vsaas-mongodb 2>/dev/null || true
    
    # Delete Secrets
    kubectl delete secret -n vsaas-dev -l app.kubernetes.io/instance=vsaas-mongodb 2>/dev/null || true
    
    log "Cleanup completed"
}

# Update main function
main() {
    parse_args "$@"
    
    log "Starting MongoDB installation process..."
    log "Using chart path: $CHART_PATH"
    log "Using VMongo path: $VMONGO_PATH"
    
    check_prerequisites
    verify_vmongo_directory
    prepare_worker_node
    cleanup_resources
    setup_storage_class
    install_mongodb
    
    local pod_name=$(wait_for_pod)
    verify_installation "$pod_name"  # Add verification step

    #local pod_name="vsaas-mongodb-0"
    
    if [ -n "$pod_name" ]; then
        copy_vmongo_data "$pod_name"
        initialize_mongodb "$pod_name"
        verify_mongodb "$pod_name"
        print_connection_info
    fi
    
    log "MongoDB installation completed successfully"
}

main "$@"