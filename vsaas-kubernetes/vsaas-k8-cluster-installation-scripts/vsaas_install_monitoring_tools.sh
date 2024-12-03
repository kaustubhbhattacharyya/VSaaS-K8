#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

###############################################################################
# Prints the script header with formatting
# Arguments:
#   None
# Outputs:
#   Writes formatted header to stdout
###############################################################################
print_header() {
    echo -e "${GREEN}================================================"
    echo -e "    Prometheus & Grafana Installation Script"
    echo -e "================================================${NC}"
}

###############################################################################
# Displays the help menu with all available options
# Arguments:
#   None
# Outputs:
#   Writes help menu to stdout with all script options and examples
###############################################################################
print_help() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]"
    echo -e "\nOptions:"
    echo -e "  -h,  --help                      Display this help message"
    echo -e "  -p,  --prometheus                Install only Prometheus"
    echo -e "  -g,  --grafana                   Install only Grafana"
    echo -e "  -a,  --all                       Install both Prometheus and Grafana"
    echo -e "  -f,  --fix-alert                 Fix AlertManager storage issues"
    echo -e "  -up, --uninstall-prometheus      Uninstall Prometheus"
    echo -e "  -ug, --uninstall-grafana        Uninstall Grafana"
    echo -e "  -ua, --uninstall-all            Uninstall both Prometheus and Grafana"
    echo -e "  -c,  --check                     Check installation status"
    echo -e "  -d,  --debug                     Show detailed debugging information"
    echo -e "\nExamples:"
    echo -e "  $0 --all                        Install both Prometheus and Grafana"
    echo -e "  $0 --prometheus                 Install only Prometheus"
    echo -e "  $0 --grafana                    Install only Grafana"
    echo -e "  $0 --fix-alert                  Fix AlertManager storage issues"
    echo -e "\nAlert Manager Fix:"
    echo -e "  The --fix-alert option will:"
    echo -e "  - Clean up existing AlertManager resources"
    echo -e "  - Recreate PV/PVC with correct configurations"
    echo -e "  - Update AlertManager StatefulSet"
    echo -e "  - Verify the fix and provide detailed status${NC}"
}


###############################################################################
# Checks if required commands exist
# Arguments:
#   $1 - Command to check
# Returns:
#   0 if command exists, 1 if it doesn't
###############################################################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
}


###############################################################################
# Creates StorageClass for dynamic provisioning
# Arguments:
#   None
# Outputs:
#   Storage class creation status
###############################################################################
create_storage_class() {
    echo -e "${GREEN}Creating Storage Class...${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: monitoring-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

    # For cloud environments, use appropriate provisioner
    # For example, for AWS:
    # provisioner: kubernetes.io/aws-ebs
    # For GCP:
    # provisioner: kubernetes.io/gce-pd
    # For Azure:
    # provisioner: kubernetes.io/azure-disk
}


###############################################################################
# Creates PersistentVolumes with correct naming for StatefulSets
# Arguments:
#   None
# Outputs:
#   PV creation status
###############################################################################
create_persistent_volumes() {
    echo -e "${GREEN}Creating Persistent Volumes...${NC}"
    local hostname=$(hostname)
    
    # Create PV for Prometheus Server
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-server
  labels:
    type: local
    app: prometheus-server
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: monitoring-storage
  hostPath:
    path: /data/prometheus-server
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${hostname}
EOF

    # Create PV for AlertManager with exact StatefulSet naming
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: storage-prometheus-alertmanager-0
  labels:
    type: local
    app: alertmanager
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: monitoring-storage
  hostPath:
    path: /data/alertmanager
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${hostname}
EOF
}


###############################################################################
# Verifies all prerequisites are met
# Arguments:
#   None
# Outputs:
#   Status messages about prerequisites
# Returns:
#   0 if all prerequisites are met, 1 if not
###############################################################################
check_prerequisites() {
    echo -e "${GREEN}Checking prerequisites...${NC}"
    
    # Check for kubectl
    if ! command_exists kubectl; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        return 1
    fi
    
    # Check for helm
    if ! command_exists helm; then
        echo -e "${RED}Error: helm is not installed${NC}"
        return 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
        return 1
    fi

    echo -e "${GREEN}All prerequisites met!${NC}"
    return 0
}


###############################################################################
# Adds the required Helm repositories
# Arguments:
#   None
# Outputs:
#   Status messages about repository addition
###############################################################################
add_helm_repos() {
    echo -e "${GREEN}Adding Helm repositories...${NC}"
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
}

###############################################################################
# Creates monitoring namespace if it doesn't exist
# Arguments:
#   None
# Outputs:
#   Status message about namespace creation
###############################################################################
create_namespace() {
    echo -e "${GREEN}Setting up monitoring namespace...${NC}"
    
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
}


###############################################################################
# Creates necessary directories on host machines
# Arguments:
#   None
# Outputs:
#   Directory creation status
###############################################################################
create_host_directories() {
    echo -e "${GREEN}Creating host directories...${NC}"
    
    # Create all required directories
    local directories=(
        "/data/prometheus-server"
        "/data/alertmanager"
        "/data/grafana"
    )
    
    for dir in "${directories[@]}"; do
        if ! sudo mkdir -p "$dir"; then
            echo -e "${RED}Failed to create directory: $dir${NC}"
            return 1
        fi
        
        if ! sudo chmod 777 "$dir"; then
            echo -e "${RED}Failed to set permissions for: $dir${NC}"
            return 1
        fi
        echo -e "${GREEN}Created and configured: $dir${NC}"
    done
}

###############################################################################
# Verifies and displays PVC details
# Arguments:
#   None
# Outputs:
#   PVC status details
###############################################################################
debug_pvc_status() {
    echo -e "\n${YELLOW}PVC Details:${NC}"
    kubectl describe pvc -n monitoring
    
    echo -e "\n${YELLOW}PV Details:${NC}"
    kubectl get pv
    
    echo -e "\n${YELLOW}Storage Class Details:${NC}"
    kubectl get sc monitoring-storage -o yaml
    
    echo -e "\n${YELLOW}Node Details:${NC}"
    kubectl get nodes --show-labels
}

###############################################################################
# Handles cleanup of existing resources
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
cleanup_existing_resources() {
    echo -e "${YELLOW}Cleaning up existing resources...${NC}"
    
    # Delete existing PVCs
    kubectl delete pvc --all -n monitoring
    
    # Delete existing PVs
    kubectl delete pv --all
    
    # Clean up directories
    sudo rm -rf /data/*
    
    # Recreate directories
    create_host_directories
    
    echo -e "${GREEN}Cleanup completed${NC}"
    return 0
}

###############################################################################
# Main installation function with cleanup
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
install_monitoring() {
    print_header
    
    # Cleanup existing resources
    if ! cleanup_existing_resources; then
        echo -e "${RED}Failed to cleanup existing resources${NC}"
        return 1
    fi
    
    # Create new storage resources
    if ! create_storage_class; then
        echo -e "${RED}Failed to create storage class${NC}"
        return 1
    fi
    
    if ! create_persistent_volumes; then
        echo -e "${RED}Failed to create persistent volumes${NC}"
        return 1
    fi
    
    # Install Prometheus
    if ! install_prometheus; then
        echo -e "${RED}Failed to install Prometheus${NC}"
        debug_pvc_status
        return 1
    fi
    
    echo -e "${GREEN}Installation completed successfully!${NC}"
    return 0
}

###############################################################################
# Updates Prometheus values with correct AlertManager StatefulSet configuration
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
create_prometheus_values() {
    local hostname=$(hostname)
    cat > prometheus-values.yaml <<EOF
alertmanager:
  enabled: true
  # StatefulSet configuration
  statefulSet:
    enabled: true
  # PVC configuration
  persistentVolume:
    enabled: true
  # Storage configuration matches PV
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: monitoring-storage
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 2Gi
  # Node selection
  nodeSelector:
    kubernetes.io/hostname: ${hostname}
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule

server:
  persistentVolume:
    enabled: true
    existingClaim: ""
    storageClass: "monitoring-storage"
    size: 10Gi
  nodeSelector:
    kubernetes.io/hostname: ${hostname}
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule

pushgateway:
  enabled: true
  persistentVolume:
    enabled: true
    storageClass: "monitoring-storage"
    size: 2Gi
  nodeSelector:
    kubernetes.io/hostname: ${hostname}

storageClass: monitoring-storage

rbac:
  create: true
  pspEnabled: false
EOF
}

###############################################################################
# Verifies AlertManager PVC binding
# Arguments:
#   None
# Returns:
#   0 if bound, 1 if not bound
###############################################################################
verify_alertmanager_storage() {
    echo -e "${GREEN}Verifying AlertManager storage...${NC}"
    
    # Check PV exists
    if ! kubectl get pv storage-prometheus-alertmanager-0 &>/dev/null; then
        echo -e "${RED}AlertManager PV not found${NC}"
        return 1
    fi
    
    # Check PVC status
    local pvc_status=$(kubectl get pvc storage-prometheus-alertmanager-0 -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$pvc_status" != "Bound" ]; then
        echo -e "${RED}AlertManager PVC not bound${NC}"
        echo -e "${YELLOW}PVC Status: $pvc_status${NC}"
        return 1
    fi
    
    echo -e "${GREEN}AlertManager storage verified successfully${NC}"
    return 0
}

###############################################################################
# Troubleshoots and fixes AlertManager storage issues
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
troubleshoot_alertmanager_storage() {
    echo -e "${YELLOW}Starting AlertManager storage troubleshooting...${NC}"
    
    # 1. Check PV status
    echo -e "\n${GREEN}Checking PV status:${NC}"
    kubectl get pv storage-prometheus-alertmanager-0 -o yaml || {
        echo -e "${RED}PV not found. Creating it...${NC}"
        create_alertmanager_pv
    }
    
    # 2. Check PVC status
    echo -e "\n${GREEN}Checking PVC status:${NC}"
    kubectl get pvc storage-prometheus-alertmanager-0 -n monitoring -o yaml || {
        echo -e "${RED}PVC not found or not bound${NC}"
    }
    
    # 3. Create PV with exact specifications
    create_alertmanager_pv
    
    # 4. Verify binding
    verify_alertmanager_binding
}

###############################################################################
# Verifies PV-PVC binding
# Arguments:
#   None
# Returns:
#   0 if bound, 1 if not bound
###############################################################################
verify_alertmanager_binding() {
    echo -e "${YELLOW}Verifying PV-PVC binding...${NC}"
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local pvc_status=$(kubectl get pvc storage-prometheus-alertmanager-0 -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$pvc_status" = "Bound" ]; then
            echo -e "${GREEN}PVC successfully bound!${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}Attempt $attempt/$max_attempts: PVC status is $pvc_status${NC}"
        echo -e "\nPV Status:"
        kubectl get pv storage-prometheus-alertmanager-0
        echo -e "\nPVC Status:"
        kubectl get pvc storage-prometheus-alertmanager-0 -n monitoring
        
        sleep 5
        ((attempt++))
    done
    
    return 1
}


###############################################################################
# Updates Prometheus values for AlertManager with correct storage settings
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
update_alertmanager_config() {
    local hostname=$(hostname)
    
    # Create values file for AlertManager
    cat > alertmanager-values.yaml <<EOF
alertmanager:
  enabled: true
  statefulSet:
    enabled: true
  persistence:
    enabled: true
    storageClass: monitoring-storage
    size: 2Gi
    selector:
      matchLabels:
        app.kubernetes.io/name: alertmanager
        app.kubernetes.io/instance: prometheus
  nodeSelector:
    kubernetes.io/hostname: ${hostname}
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
EOF

    # Upgrade Prometheus with new values
    helm upgrade prometheus prometheus-community/prometheus \
        --namespace monitoring \
        --values alertmanager-values.yaml \
        --reuse-values
}


###############################################################################
# Creates AlertManager PV with correct matching labels
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
create_alertmanager_pv() {
    local hostname=$(hostname)
    
    # Delete existing PV if it exists
    kubectl delete pv storage-prometheus-alertmanager-0 2>/dev/null || true
    
    # Create new PV with correct labels
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: storage-prometheus-alertmanager-0
  labels:
    app.kubernetes.io/name: alertmanager
    app.kubernetes.io/instance: prometheus
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: monitoring-storage
  hostPath:
    path: /data/alertmanager
    type: DirectoryOrCreate
  claimRef:
    namespace: monitoring
    name: storage-prometheus-alertmanager-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${hostname}
EOF
}


###############################################################################
# Handles complete cleanup and setup of AlertManager storage
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
fix_alertmanager() {
    echo -e "${GREEN}Starting AlertManager fix...${NC}"
    
    # 1. Complete cleanup
    echo -e "${YELLOW}Performing complete cleanup...${NC}"
    # Delete StatefulSet first to release PVC
    kubectl delete statefulset prometheus-alertmanager -n monitoring --force --grace-period=0 2>/dev/null || true
    sleep 5
    
    # Delete PVC
    kubectl delete pvc storage-prometheus-alertmanager-0 -n monitoring --force --grace-period=0 2>/dev/null || true
    sleep 5
    
    # Delete PV
    kubectl delete pv storage-prometheus-alertmanager-0 --force --grace-period=0 2>/dev/null || true
    sleep 5
    
    # Clean storage
    sudo rm -rf /data/alertmanager
    sudo mkdir -p /data/alertmanager
    sudo chmod 777 /data/alertmanager
    
    # 2. Create storage class if it doesn't exist
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: monitoring-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
    
    # 3. Create PV
    if ! create_alertmanager_pv; then
        echo -e "${RED}Failed to create PV${NC}"
        return 1
    fi
    
    # 4. Create PVC explicitly
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-prometheus-alertmanager-0
  namespace: monitoring
  labels:
    app.kubernetes.io/name: alertmanager
    app.kubernetes.io/instance: prometheus
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: monitoring-storage
  resources:
    requests:
      storage: 2Gi
  selector:
    matchLabels:
      app.kubernetes.io/name: alertmanager
      app.kubernetes.io/instance: prometheus
EOF
    
    # 5. Wait for PVC to bind
    echo -e "${YELLOW}Waiting for PVC to bind...${NC}"
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl get pvc storage-prometheus-alertmanager-0 -n monitoring | grep -q Bound; then
            echo -e "${GREEN}PVC successfully bound!${NC}"
            break
        fi
        echo -e "${YELLOW}Attempt $attempt/$max_attempts: Waiting for PVC to bind...${NC}"
        kubectl get pvc storage-prometheus-alertmanager-0 -n monitoring
        sleep 5
        ((attempt++))
    done
    
    # 6. Update AlertManager configuration
    if ! update_alertmanager_config; then
        echo -e "${RED}Failed to update AlertManager configuration${NC}"
        return 1
    fi
    
    # 7. Final verification
    echo -e "\n${YELLOW}Final Status:${NC}"
    kubectl get pv,pvc -n monitoring | grep alertmanager
    kubectl get pods -n monitoring | grep alertmanager
    
    return 0
}

###############################################################################
# Verifies the complete fix
# Arguments:
#   None
# Returns:
#   0 if verification succeeds, 1 if it fails
###############################################################################
verify_fix() {
    echo -e "${YELLOW}Verifying fix...${NC}"
    
    # Wait for pod to be ready
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl get pods -n monitoring prometheus-alertmanager-0 | grep -q Running; then
            echo -e "${GREEN}AlertManager pod is running!${NC}"
            return 0
        fi
        echo -e "${YELLOW}Attempt $attempt/$max_attempts: Waiting for AlertManager pod...${NC}"
        kubectl get pods -n monitoring | grep alertmanager
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}Failed to verify fix${NC}"
    return 1
}

###############################################################################
# Cleanup function specific to AlertManager
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
cleanup_alertmanager() {
    echo -e "${YELLOW}Cleaning up AlertManager resources...${NC}"
    
    # Delete the StatefulSet
    kubectl delete statefulset prometheus-alertmanager -n monitoring --force --grace-period=0 2>/dev/null || true
    
    # Delete the PVC
    kubectl delete pvc storage-prometheus-alertmanager-0 -n monitoring --force --grace-period=0 2>/dev/null || true
    
    # Delete the PV
    kubectl delete pv storage-prometheus-alertmanager-0 --force --grace-period=0 2>/dev/null || true
    
    # Clean up the directory
    sudo rm -rf /data/alertmanager
    
    # Recreate directory
    sudo mkdir -p /data/alertmanager
    sudo chmod 777 /data/alertmanager
    
    echo -e "${GREEN}AlertManager cleanup completed${NC}"
    return 0
}

###############################################################################
# Verifies PVC binding status
# Arguments:
#   None
# Returns:
#   0 if all PVCs are bound, 1 otherwise
###############################################################################
verify_pvc_binding() {
    echo -e "${GREEN}Verifying PVC binding status...${NC}"
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local unbound_pvcs=$(kubectl get pvc -n monitoring -o jsonpath='{.items[?(@.status.phase!="Bound")].metadata.name}')
        
        if [ -z "$unbound_pvcs" ]; then
            echo -e "${GREEN}All PVCs are bound successfully!${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}Waiting for PVCs to bind... Attempt $attempt/$max_attempts${NC}"
        echo -e "${YELLOW}Unbound PVCs: $unbound_pvcs${NC}"
        
        # Display PVC details for debugging
        echo -e "\n${YELLOW}PVC Status:${NC}"
        kubectl get pvc -n monitoring
        
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}Failed to bind PVCs within timeout period${NC}"
    return 1
}

###############################################################################
# Installs Prometheus with enhanced error handling
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
###############################################################################
install_prometheus() {
    print_header
    echo -e "${GREEN}Installing Prometheus...${NC}"
    
    # Create namespace
    create_namespace
    
    # Create and verify storage prerequisites
    if ! create_host_directories; then
        echo -e "${RED}Failed to create host directories${NC}"
        return 1
    fi
    
    if ! create_storage_class; then
        echo -e "${RED}Failed to create storage class${NC}"
        return 1
    fi
    
    if ! create_persistent_volumes; then
        echo -e "${RED}Failed to create persistent volumes${NC}"
        return 1
    fi
    
    # Create Prometheus values
    if ! create_prometheus_values; then
        echo -e "${RED}Failed to create Prometheus values${NC}"
        return 1
    fi
    
    # Install Prometheus
    echo -e "${GREEN}Deploying Prometheus...${NC}"
    if ! helm install prometheus prometheus-community/prometheus \
        --namespace monitoring \
        --values prometheus-values.yaml \
        --timeout 10m; then
        echo -e "${RED}Failed to install Prometheus${NC}"
        return 1
    fi
    
    # Verify PVC binding
    if ! verify_pvc_binding; then
        echo -e "${RED}PVC binding verification failed${NC}"
        # Show pod status for debugging
        echo -e "\n${YELLOW}Pod Status:${NC}"
        kubectl get pods -n monitoring
        echo -e "\n${YELLOW}PV Status:${NC}"
        kubectl get pv
        echo -e "\n${YELLOW}PVC Status:${NC}"
        kubectl get pvc -n monitoring
        return 1
    fi
    
    echo -e "${GREEN}Prometheus installation completed successfully!${NC}"
    return 0
}


###############################################################################
# Verifies Prometheus installation
# Arguments:
#   None
# Returns:
#   0 if verification succeeds, 1 if it fails
###############################################################################
verify_prometheus_installation() {
    echo -e "\n${GREEN}Verifying Prometheus installation...${NC}"
    
    # Check required components
    local components=("prometheus-server" "prometheus-alertmanager" "prometheus-pushgateway")
    
    for component in "${components[@]}"; do
        if ! kubectl get pods -n monitoring -l "app=$component" -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
            echo -e "${RED}Component $component is not running${NC}"
            return 1
        fi
    done
    
    # Check services
    for component in "${components[@]}"; do
        if ! kubectl get svc -n monitoring -l "app=$component" &>/dev/null; then
            echo -e "${RED}Service for $component not found${NC}"
            return 1
        fi
    done
    
    return 0
}

###############################################################################
# Displays Prometheus access information
# Arguments:
#   None
###############################################################################
display_prometheus_access_info() {
    echo -e "\n${GREEN}Prometheus Access Information:${NC}"
    
    echo -e "\n${YELLOW}Prometheus Server:${NC}"
    echo "kubectl port-forward svc/prometheus-server 9090:80 -n monitoring"
    echo "Access: http://localhost:9090"
    
    echo -e "\n${YELLOW}Alert Manager:${NC}"
    echo "kubectl port-forward svc/prometheus-alertmanager 9093:9093 -n monitoring"
    echo "Access: http://localhost:9093"
    
    echo -e "\n${YELLOW}Push Gateway:${NC}"
    echo "kubectl port-forward svc/prometheus-pushgateway 9091:9091 -n monitoring"
    echo "Access: http://localhost:9091"
}


###############################################################################
# Gets and displays access information for Prometheus components
# Arguments:
#   None
# Outputs:
#   Access URLs and credentials
###############################################################################
get_prometheus_access() {
    echo -e "\n${YELLOW}Prometheus Access Information:${NC}"
    
    # Prometheus Server
    echo -e "\n${GREEN}Prometheus Server:${NC}"
    echo "kubectl port-forward -n monitoring svc/prometheus-server 9090:80"
    echo "Then access: http://localhost:9090"
    
    # Pushgateway
    echo -e "\n${GREEN}Prometheus Pushgateway:${NC}"
    echo "kubectl port-forward -n monitoring svc/prometheus-pushgateway 9091:9091"
    echo "Then access: http://localhost:9091"
    
    # AlertManager
    echo -e "\n${GREEN}Prometheus AlertManager:${NC}"
    echo "kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:80"
    echo "Then access: http://localhost:9093"
}


###############################################################################
# Installs Grafana with storage configuration
# Arguments:
#   None
# Outputs:
#   Installation progress and status messages
###############################################################################
install_grafana() {
    echo -e "${GREEN}Installing Grafana...${NC}"
    
    # Create values file for Grafana
    cat <<EOF > grafana-values.yaml
persistence:
  enabled: true
  storageClassName: monitoring-storage
  size: 10Gi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true

tolerations:
  - key: "node-role.kubernetes.io/master"
    operator: "Exists"
    effect: "NoSchedule"

nodeSelector:
  kubernetes.io/hostname: $(hostname)
EOF

    # Install Grafana
    helm install grafana grafana/grafana \
        --namespace monitoring \
        --values grafana-values.yaml

    # Wait for pod with proper timeout
    echo "Waiting for Grafana pod to be ready..."
    kubectl wait --for=condition=Ready pods -l "app.kubernetes.io/name=grafana" -n monitoring --timeout=300s
}


###############################################################################
# Verifies PVC and PV status
# Arguments:
#   None
# Outputs:
#   Storage component status
###############################################################################
verify_storage() {
    echo -e "\n${YELLOW}Verifying Storage Components:${NC}"
    
    echo -e "\n${GREEN}Storage Classes:${NC}"
    kubectl get sc
    
    echo -e "\n${GREEN}Persistent Volumes:${NC}"
    kubectl get pv
    
    echo -e "\n${GREEN}Persistent Volume Claims:${NC}"
    kubectl get pvc -n monitoring
}

###############################################################################
# Gets and displays access information for Grafana
# Arguments:
#   None
# Outputs:
#   Access URLs and credentials
###############################################################################
get_grafana_access() {
    echo -e "\n${YELLOW}Grafana Access Information:${NC}"
    echo -e "\n${GREEN}Access URL:${NC}"
    echo "kubectl port-forward -n monitoring svc/grafana 3000:80"
    echo "Then access: http://localhost:3000"
    
    echo -e "\n${GREEN}Credentials:${NC}"
    echo "Username: admin"
    echo "Password: admin123"
}


###############################################################################
# Installs both Prometheus and Grafana
# Arguments:
#   None
# Outputs:
#   Installation progress and status messages
###############################################################################
install_all() {
    print_header
    echo -e "${GREEN}Installing Prometheus and Grafana...${NC}"
    
    install_prometheus
    install_grafana
    
    echo -e "${GREEN}Installation completed! Access details:${NC}"
    echo -e "Prometheus: kubectl port-forward svc/prometheus-server 9090:80 -n monitoring"
    echo -e "Grafana: kubectl port-forward svc/grafana 3000:80 -n monitoring"
}

###############################################################################
# Verifies the installation of both Prometheus and Grafana
# Arguments:
#   None
# Outputs:
#   Verification status and any issues found
###############################################################################
verify_installation() {
    echo -e "\n${YELLOW}Verifying Installation:${NC}"
    
    # Check Prometheus components
    echo -e "\n${GREEN}Prometheus Components:${NC}"
    kubectl get pods -n monitoring -l "app=prometheus" -o wide
    
    # Check Grafana
    echo -e "\n${GREEN}Grafana Components:${NC}"
    kubectl get pods -n monitoring -l "app.kubernetes.io/name=grafana" -o wide
    
    # Check Services
    echo -e "\n${GREEN}Services:${NC}"
    kubectl get svc -n monitoring
    
    # Check PVCs
    echo -e "\n${GREEN}Persistent Volume Claims:${NC}"
    kubectl get pvc -n monitoring
}


###############################################################################
# Uninstalls Prometheus
# Arguments:
#   None
# Outputs:
#   Uninstallation progress and status messages
###############################################################################
uninstall_prometheus() {
    print_header
    echo -e "${YELLOW}Uninstalling Prometheus...${NC}"
    
    helm uninstall prometheus -n monitoring
    kubectl delete pvc -l app=prometheus -n monitoring
    
    echo -e "${GREEN}Prometheus uninstalled successfully!${NC}"
}

###############################################################################
# Uninstalls Grafana
# Arguments:
#   None
# Outputs:
#   Uninstallation progress and status messages
###############################################################################
uninstall_grafana() {
    print_header
    echo -e "${YELLOW}Uninstalling Grafana...${NC}"
    
    helm uninstall grafana -n monitoring
    kubectl delete pvc -l app.kubernetes.io/name=grafana -n monitoring
    
    echo -e "${GREEN}Grafana uninstalled successfully!${NC}"
}

###############################################################################
# Uninstalls both Prometheus and Grafana
# Arguments:
#   None
# Outputs:
#   Uninstallation progress and status messages
###############################################################################
uninstall_all() {
    print_header
    echo -e "${YELLOW}Uninstalling Prometheus and Grafana...${NC}"
    
    uninstall_prometheus
    uninstall_grafana
    
    # Clean up namespace if empty
    if [ -z "$(kubectl get all -n monitoring 2>/dev/null)" ]; then
        kubectl delete namespace monitoring
    fi
    
    echo -e "${GREEN}All components uninstalled successfully!${NC}"
}

###############################################################################
# Checks installation status of Prometheus and Grafana
# Arguments:
#   None
# Outputs:
#   Current status of installations and their components
###############################################################################
check_status() {
    print_header
    echo -e "${GREEN}Checking installation status...${NC}"
    
    echo -e "\n${YELLOW}Prometheus Status:${NC}"
    kubectl get all -n monitoring -l app=prometheus 2>/dev/null || echo "Prometheus not installed"
    
    echo -e "\n${YELLOW}Grafana Status:${NC}"
    kubectl get all -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null || echo "Grafana not installed"
    
    echo -e "\n${YELLOW}Persistent Volumes:${NC}"
    kubectl get pvc -n monitoring
}

###############################################################################
# Sets up helm repositories based on requirements
# Arguments:
#   $1 - Component to install (prometheus, grafana, or all)
# Returns:
#   0 on success, 1 on failure
###############################################################################
setup_helm_repos() {
    local component=$1
    echo -e "${GREEN}Setting up Helm repositories...${NC}"
    
    case $component in
        "prometheus")
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
            ;;
        "grafana")
            helm repo add grafana https://grafana.github.io/helm-charts
            ;;
        "all")
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
            helm repo add grafana https://grafana.github.io/helm-charts
            ;;
    esac
    
    helm repo update
    return $?
}

###############################################################################
# Initializes monitoring environment
# Arguments:
#   $1 - Component to initialize (prometheus, grafana, or all)
# Returns:
#   0 on success, 1 on failure
###############################################################################
initialize_monitoring() {
    local component=$1
    
    echo -e "${GREEN}Initializing monitoring environment...${NC}"
    
    # Setup Helm repositories
    if ! setup_helm_repos "$component"; then
        echo -e "${RED}Failed to setup Helm repositories${NC}"
        return 1
    fi
    
    # Setup storage prerequisites
    if ! create_host_directories; then
        echo -e "${RED}Failed to create host directories${NC}"
        return 1
    fi
    
    if ! create_storage_class; then
        echo -e "${RED}Failed to create storage class${NC}"
        return 1
    fi
    
    if ! create_persistent_volumes; then
        echo -e "${RED}Failed to create persistent volumes${NC}"
        return 1
    fi
    
    return 0
}

###############################################################################
# Handles the complete installation process
# Arguments:
#   $1 - Installation type (prometheus, grafana, or all)
# Returns:
#   0 on success, 1 on failure
###############################################################################
handle_installation() {
    local install_type=$1
    
    # Cleanup first
    if ! cleanup_existing_resources; then
        echo -e "${RED}Cleanup failed${NC}"
        return 1
    fi
    
    # Initialize environment
    if ! initialize_monitoring "$install_type"; then
        echo -e "${RED}Initialization failed${NC}"
        return 1
    fi
    
    # Perform installation based on type
    case $install_type in
        "prometheus")
            install_prometheus
            local install_status=$?
            ;;
        "grafana")
            install_grafana
            local install_status=$?
            ;;
        "all")
            install_prometheus && install_grafana
            local install_status=$?
            ;;
    esac
    
    if [ $install_status -ne 0 ]; then
        echo -e "${RED}Installation failed${NC}"
        return 1
    fi
    
    # Verify storage
    verify_storage
    
    # Display access information
    display_access_info "$install_type"
    
    return 0
}

###############################################################################
# Displays AlertManager status information
# Arguments:
#   None
# Outputs:
#   Status information about AlertManager
###############################################################################
display_alertmanager_status() {
    echo -e "\n${GREEN}AlertManager Status:${NC}"
    
    # Show PV status
    echo -e "\n${YELLOW}PV Status:${NC}"
    kubectl get pv | grep alertmanager
    
    # Show PVC status
    echo -e "\n${YELLOW}PVC Status:${NC}"
    kubectl get pvc -n monitoring | grep alertmanager
    
    # Show pod status
    echo -e "\n${YELLOW}Pod Status:${NC}"
    kubectl get pods -n monitoring | grep alertmanager
    
    # Show service status
    echo -e "\n${YELLOW}Service Status:${NC}"
    kubectl get svc -n monitoring | grep alertmanager
    
    # Show access information
    echo -e "\n${GREEN}Access Information:${NC}"
    echo "kubectl port-forward svc/prometheus-alertmanager 9093:9093 -n monitoring"
    echo "Then access: http://localhost:9093"
}

###############################################################################
# Shows detailed debugging information
# Arguments:
#   None
# Outputs:
#   Detailed debug information about the monitoring stack
###############################################################################
show_debug_info() {
    echo -e "${GREEN}Gathering debug information...${NC}"
    
    # Show node information
    echo -e "\n${YELLOW}Node Information:${NC}"
    kubectl get nodes -o wide
    
    # Show storage classes
    echo -e "\n${YELLOW}Storage Classes:${NC}"
    kubectl get sc
    
    # Show PV/PVC status
    echo -e "\n${YELLOW}Storage Status:${NC}"
    kubectl get pv,pvc -n monitoring
    
    # Show pod status
    echo -e "\n${YELLOW}Pod Status:${NC}"
    kubectl get pods -n monitoring -o wide
    
    # Show AlertManager specific information
    echo -e "\n${YELLOW}AlertManager Details:${NC}"
    kubectl describe statefulset prometheus-alertmanager -n monitoring
    
    # Show recent events
    echo -e "\n${YELLOW}Recent Events:${NC}"
    kubectl get events -n monitoring --sort-by='.lastTimestamp' | tail -n 20
    
    # Show logs if AlertManager pod exists
    if kubectl get pod prometheus-alertmanager-0 -n monitoring &>/dev/null; then
        echo -e "\n${YELLOW}AlertManager Logs:${NC}"
        kubectl logs prometheus-alertmanager-0 -n monitoring --tail=50
    fi
}

###############################################################################
# Displays access information for installed components
# Arguments:
#   $1 - Component type (prometheus, grafana, or all)
###############################################################################
display_access_info() {
    local component=$1
    
    echo -e "\n${GREEN}Access Information:${NC}"
    
    case $component in
        "prometheus"|"all")
            echo -e "\nPrometheus:"
            echo -e "kubectl port-forward svc/prometheus-server 9090:80 -n monitoring"
            echo -e "Access URL: http://localhost:9090"
            ;;
    esac
    
    case $component in
        "grafana"|"all")
            echo -e "\nGrafana:"
            echo -e "kubectl port-forward svc/grafana 3000:80 -n monitoring"
            echo -e "Access URL: http://localhost:3000"
            echo -e "Username: admin"
            echo -e "${GREEN}Password:${NC} $(kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)"
            ;;
    esac
}

###############################################################################
# Main script execution
# Arguments:
#   Command line arguments
# Returns:
#   0 on success, 1 on failure
###############################################################################
main() {
    # Parse command line arguments
    case "$1" in
        -h|--help)
            print_help
            ;;
        -p|--prometheus)
            handle_installation "prometheus"
            ;;
        -g|--grafana)
            handle_installation "grafana"
            ;;
        -a|--all)
            handle_installation "all"
            ;;
        -f|--fix-alert)
            if fix_alertmanager; then
                echo -e "${GREEN}AlertManager fix completed successfully!${NC}"
                display_alertmanager_status
            else
                echo -e "${RED}AlertManager fix failed. See above for details.${NC}"
                exit 1
            fi
            ;;
        -up|--uninstall-prometheus)
            uninstall_prometheus
            ;;
        -ug|--uninstall-grafana)
            uninstall_grafana
            ;;
        -ua|--uninstall-all)
            uninstall_all
            ;;
        -c|--check)
            check_status
            ;;
        -d|--debug)
            show_debug_info
            ;;
        *)
            echo -e "${RED}Error: Invalid option${NC}"
            print_help
            exit 1
            ;;
    esac
}



# Execute main function with all arguments
main "$@"

# Main script logic
# case "$1" in
#     -h|--help)
#         print_help
#         ;;
#     -p|--prometheus)
#         helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#         helm repo update
#         create_host_directories
#         create_storage_class
#         create_persistent_volumes
#         install_prometheus
#         verify_storage
#         ;;
#     -g|--grafana)
#         helm repo add grafana https://grafana.github.io/helm-charts
#         helm repo update
#         create_host_directories
#         create_storage_class
#         create_persistent_volumes
#         install_grafana
#         verify_storage
#         ;;
#     -a|--all)
#         helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#         helm repo add grafana https://grafana.github.io/helm-charts
#         helm repo update
#         create_host_directories
#         create_storage_class
#         create_persistent_volumes
#         install_all
#         verify_storage
#         ;;
#     -up|--uninstall-prometheus)
#         uninstall_prometheus
#         ;;
#     -ug|--uninstall-grafana)
#         uninstall_grafana
#         ;;
#     -ua|--uninstall-all)
#         uninstall_all
#         ;;
#     -c|--check)
#         check_status
#         ;;
#     *)
#         echo -e "${RED}Error: Invalid option${NC}"
#         print_help
#         exit 1
#         ;;
# esac