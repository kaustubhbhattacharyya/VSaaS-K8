


readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly CONFIG_FILE="${SCRIPT_DIR}/install-config.yaml"
readonly LOG_FILE="${SCRIPT_DIR}/mongodb-install.log"


NAMESPACE="vsaas-dev"
RELEASE_NAME="vsaas-mongodb"
VMONGO_PATH="./VMongo"
WORKER_NODE="vsaas-workernode-3"
STORAGE_PATH="/data/mongodb"
TIMEOUT=300


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


check_prerequisites() {
    log "Checking prerequisites..."
    
    
    local required_commands=("kubectl" "helm" "ssh" "mongosh")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' not found"
        fi
    done

    
    if [ ! -d "$VMONGO_PATH" ]; then
        error "VMongo directory not found at $VMONGO_PATH"
    fi

    
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi

    log "Prerequisites check completed"
}


prepare_worker_node() {
    log "Preparing worker node..."
    
    
    if ! ssh root@$WORKER_NODE "mkdir -p $STORAGE_PATH && chmod -R 777 $STORAGE_PATH"; then
        error "Failed to create storage directory on worker node"
    fi

    log "Worker node preparation completed"
}


cleanup_resources() {
    log "Cleaning up existing resources..."
    
    helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
    kubectl delete pvc -n $NAMESPACE $RELEASE_NAME-pvc 2>/dev/null || true
    kubectl delete pv $RELEASE_NAME-pv 2>/dev/null || true
    
    
    sleep 5
    
    log "Cleanup completed"
}


install_mongodb() {
    log "Installing MongoDB using Helm..."
    
    
    log "Verifying existing resources..."
    kubectl get all -n $NAMESPACE
    
    if ! helm upgrade --install $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --wait \
        --debug \
        --timeout ${TIMEOUT}s; then
        error "Failed to install MongoDB"
    fi
    
    log "MongoDB installation completed"
    
    
    log "Deployed resources:"
    kubectl get all -n $NAMESPACE
    
    
    log "Recent events:"
    kubectl get events -n $NAMESPACE --sort-by='.metadata.creationTimestamp' | tail -n 10
}


wait_for_pod() {
    log "Waiting for MongoDB pod to be ready..."
    
    local counter=0
    local max_attempts=60  
    local pod_name=""
    
    while [ $counter -lt $max_attempts ]; do
        
        pod_name=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vsaas-mongodb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$pod_name" ]; then
            
            pod_status=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)
            
            if [ "$pod_status" = "Running" ]; then
                
                container_ready=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
                
                if [ "$container_ready" = "true" ]; then
                    log "Pod $pod_name is ready"
                    echo "$pod_name"
                    return 0
                fi
            fi
            
            
            if [ -n "$pod_status" ]; then
                log "Pod status: $pod_status (attempt $counter of $max_attempts)"
                
                
                if [ "$pod_status" != "Running" ]; then
                    kubectl describe pod $pod_name -n $NAMESPACE
                fi
            fi
        fi
        
        counter=$((counter + 1))
        echo -n "."
        sleep 5
    done
    
    error "Timeout waiting for MongoDB pod to be ready"
}


copy_vmongo_data() {
    local pod_name=$1
    log "Copying VMongo data to pod $pod_name..."
    
    if ! kubectl cp $VMONGO_PATH $NAMESPACE/$pod_name:/data/vmongo; then
        error "Failed to copy VMongo data"
    fi
    
    log "VMongo data copy completed"
}


initialize_mongodb() {
    local pod_name=$1
    log "Initializing MongoDB..."
    
    kubectl exec -n $NAMESPACE $pod_name -- bash -c "
        set -e
        
        if [ -f '/data/vmongo/file.js' ]; then
            echo 'Running initialization script...'
            mongosh --username \$MONGO_INITDB_ROOT_USERNAME \
                    --password \$MONGO_INITDB_ROOT_PASSWORD \
                    < /data/vmongo/file.js
        fi
        
        if [ -d '/data/vmongo/dump' ]; then
            echo 'Restoring database from dump...'
            mongorestore --username \$MONGO_INITDB_ROOT_USERNAME \
                        --password \$MONGO_INITDB_ROOT_PASSWORD \
                        /data/vmongo/dump/
        fi
    " || error "Failed to initialize MongoDB"
    
    log "MongoDB initialization completed"
}


verify_mongodb() {
    local pod_name=$1
    log "Verifying MongoDB installation..."
    
    if ! kubectl exec -n $NAMESPACE $pod_name -- mongosh \
        --username \$MONGO_INITDB_ROOT_USERNAME \
        --password \$MONGO_INITDB_ROOT_PASSWORD \
        --eval "db.adminCommand('ping')"; then
        error "MongoDB verification failed"
    fi
    
    log "MongoDB verification completed"
}

verify_installation() {
    local pod_name=$1
    
    log "Verifying installation..."
    
    
    log "StatefulSet status:"
    kubectl get statefulset -n $NAMESPACE
    
    
    log "PVC status:"
    kubectl get pvc -n $NAMESPACE
    
    
    log "ConfigMap status:"
    kubectl get configmap -n $NAMESPACE
    
    
    log "Service status:"
    kubectl get svc -n $NAMESPACE
    
    
    log "Pod details:"
    kubectl describe pod $pod_name -n $NAMESPACE
}


print_connection_info() {
    log "MongoDB Connection Information:"
    local node_ip=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}")
    local node_port=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME -o jsonpath="{.spec.ports[0].nodePort}")
    
    echo -e "\nConnection String: mongodb://root:root@central1234@$node_ip:$node_port"
    echo -e "Namespace: $NAMESPACE"
    echo -e "Release: $RELEASE_NAME"
}


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
    
    
    

    local pod_name="vsaas-mongodb-0"
    
    if [ -n "$pod_name" ]; then
        copy_vmongo_data "$pod_name"
        initialize_mongodb "$pod_name"
        verify_mongodb "$pod_name"
        print_connection_info
    fi
    
    log "MongoDB installation completed successfully"
}


main "$@"