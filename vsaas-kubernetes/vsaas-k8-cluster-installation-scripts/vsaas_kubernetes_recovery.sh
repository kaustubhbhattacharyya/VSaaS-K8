


set -euo pipefail


MASTER_IP="10.3.0.2"
POD_NETWORK_CIDR="192.168.0.0/16"
CALICO_VERSION="v3.26.1"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 


log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


command_exists() {
    command -v "$1" >/dev/null 2>&1
}


check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}


fix_dns_resolution() {
    log_info "Fixing DNS resolution..."
    mkdir -p /run/systemd/resolve/
    echo "nameserver 8.8.8.8" > /run/systemd/resolve/resolv.conf
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
}


check_services() {
    local services=("kubelet" "containerd")
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log_warn "Service $service is not running. Attempting to start..."
            systemctl start "$service"
            systemctl enable "$service"
        else
            log_info "Service $service is running"
        fi
    done
}


cleanup_network() {
    log_info "Cleaning up network interfaces..."
    ip link delete cali0 2>/dev/null || true
    ip link delete tunl0 2>/dev/null || true
    ip link delete vxlan.calico 2>/dev/null || true
    rm -rf /etc/cni/net.d/*
}


reset_kubernetes() {
    log_info "Resetting Kubernetes configuration..."
    systemctl stop kubelet || true
    kubeadm reset --force
    rm -rf /etc/kubernetes/manifests/*
    rm -rf /var/lib/etcd/*
    rm -rf $HOME/.kube/config
}


init_master() {
    log_info "Initializing master node..."
    kubeadm init --pod-network-cidr="$POD_NETWORK_CIDR" --control-plane-endpoint="$MASTER_IP" --v=5
    
    
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
}


install_calico() {
    log_info "Installing Calico network plugin..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml
}


wait_for_cluster() {
    log_info "Waiting for cluster to be ready..."
    local timeout=300
    local interval=10
    local elapsed=0
    
    while ! kubectl get nodes &>/dev/null; do
        if [ "$elapsed" -gt "$timeout" ]; then
            log_error "Timeout waiting for cluster to be ready"
            return 1
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        log_info "Still waiting for cluster... ($elapsed seconds elapsed)"
    done
    
    log_info "Cluster is ready!"
}


generate_join_command() {
    log_info "Generating join command..."
    kubeadm token create --print-join-command
}


fix_worker_node() {
    local worker_ip="$1"
    local username="$2"
    local password="$3"
    
    if ! command_exists sshpass; then
        apt-get update && apt-get install -y sshpass
    fi
    
    log_info "Fixing worker node at $worker_ip..."
    
    
    cat > /tmp/worker_fix.sh <<'EOF'

set -euo pipefail


systemctl stop kubelet
kubeadm reset --force


ip link delete cali0 2>/dev/null || true
ip link delete tunl0 2>/dev/null || true
ip link delete vxlan.calico 2>/dev/null || true
rm -rf /etc/cni/net.d/*


mkdir -p /run/systemd/resolve/
echo "nameserver 8.8.8.8" > /run/systemd/resolve/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf


systemctl start kubelet
systemctl enable kubelet
EOF
    
    
    sshpass -p "$password" scp -o StrictHostKeyChecking=no /tmp/worker_fix.sh "$username@$worker_ip:/tmp/"
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$worker_ip" "chmod +x /tmp/worker_fix.sh && sudo /tmp/worker_fix.sh"
    
    
    local join_cmd=$(kubeadm token create --print-join-command)
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$worker_ip" "sudo $join_cmd"
    
    
    rm -f /tmp/worker_fix.sh
}


verify_cluster() {
    log_info "Verifying cluster health..."
    
    
    kubectl get nodes
    
    
    kubectl get pods --all-namespaces
    
    
    kubectl get componentstatuses || true
    
    
    kubectl get svc --all-namespaces
}


main() {
    local worker_ips=()
    local username=""
    local password=""
    
    
    while [[ $
        case $1 in
            --worker-ip)
                worker_ips+=("$2")
                shift 2
                ;;
            --username)
                username="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            *)
                log_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    
    if [[ ${
        log_error "Usage: $0 --worker-ip <ip> [--worker-ip <ip>...] --username <username> --password <password>"
        exit 1
    fi
    
    
    check_root
    fix_dns_resolution
    check_services
    cleanup_network
    reset_kubernetes
    init_master
    install_calico
    wait_for_cluster
    
    
    for worker_ip in "${worker_ips[@]}"; do
        fix_worker_node "$worker_ip" "$username" "$password"
    done
    
    verify_cluster
    log_info "Cluster recovery completed successfully!"
}


main "$@"