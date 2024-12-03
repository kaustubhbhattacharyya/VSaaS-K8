#!/bin/bash

set -euo pipefail

# Configuration
KUBE_VERSION="1.27.4"
CALICO_VERSION="v3.26.1"
POD_CIDR="192.168.0.0/16"

# Global variables
MASTER_IP=""
WORKER_IPS=()
SSH_USER="root"
SSH_PASS="root"  # Default password
SSH_KEY_PATH=""
USE_SSH_KEY=false
UNINSTALL=false

# Function: print_header
# Description: Prints a formatted header for better visual separation of steps
# Arguments:
#   $1 - Header text to display
# Output: Prints a decorated header to stdout
print_header() {
    local text="$1"
    local width=80
    local padding=$(( (width - ${#text} - 2) / 2 ))
    local line=$(printf '%*s' "$width" | tr ' ' '=')
    echo -e "\n${line}"
    printf "%*s %s %*s\n" $padding '' "$text" $padding ''
    echo -e "${line}\n"
}

# Function: display_help
# Description: Displays the help information for the script, including usage and available options.
# Arguments: None
# Output: Prints help text to stdout
display_help() {
    cat << EOF
Kubernetes Cluster Setup Script
Usage: $0 [OPTIONS]

Options:
  -h, --help               Display this help message and exit
  -m, --master IP         Specify the master node IP
  -w, --worker IP         Specify a worker node IP (can be used multiple times)
  -u, --user USERNAME     Specify the SSH user (default: root)
  -p, --password PASS     Specify the SSH password (default: root)
  -k, --key PATH         Specify the SSH private key path (optional)
  --uninstall            Uninstall Kubernetes cluster from all nodes

Example:
  $0 -m 192.168.1.100 -w 192.168.1.101 -w 192.168.1.102 -u myuser -p mypassword
  $0 -m 192.168.1.100 -w 192.168.1.101 -w 192.168.1.102 -u myuser -k /path/to/private_key
  $0 --uninstall -m 192.168.1.100 -w 192.168.1.101 -w 192.168.1.102 -u myuser -p mypassword

Prerequisites:
  - Ubuntu-based system on all nodes
  - SSH access to all nodes with either password or key authentication
  - Sudo privileges on all nodes
  - Minimum 2 CPU cores and 2GB RAM per node
  - sshpass package if using password authentication (will be installed automatically)
EOF
}


# Function: check_prerequisites
# Description: Checks and installs necessary prerequisites for the script
# Arguments: None
# Output: None, but may exit on failure
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check for sshpass if using password authentication
    if [ "$USE_SSH_KEY" = false ] && ! command -v sshpass &> /dev/null; then
        echo "Installing sshpass..."
        sudo apt update
        sudo apt install -y sshpass
        check_success "Failed to install sshpass"
    fi
}

verify_repos() {
    local ip=$1
    run_ssh_command "$ip" "
        echo 'Verifying repository setup...'
        apt update 2>&1 | grep -i error || true
        ls -l /etc/apt/sources.list.d/
        ls -l /etc/apt/keyrings/
        apt-cache policy kubectl
    "
}


# Function: parse_arguments
# Description: Parses command line arguments and sets global variables accordingly.
# Arguments: All command line arguments ($@)
# Output: None, but sets global variables and may exit the script on error
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_help
                exit 0
                ;;
            -m|--master)
                MASTER_IP="$2"
                shift 2
                ;;
            -w|--worker)
                WORKER_IPS+=("$2")
                shift 2
                ;;
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -p|--password)
                SSH_PASS="$2"
                USE_SSH_KEY=false
                shift 2
                ;;
            -k|--key)
                SSH_KEY_PATH="$2"
                USE_SSH_KEY=true
                shift 2
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                display_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$MASTER_IP" || ${#WORKER_IPS[@]} -eq 0 ]]; then
        echo "Error: Master IP and at least one worker IP must be specified."
        display_help
        exit 1
    fi
}


# Function: uninstall_kubernetes
# Description: Uninstalls Kubernetes and related components from a node
# Arguments:
#   $1 - IP address of the node to uninstall from
#   $2 - Node type (master/worker)
# Output: None, but executes uninstall commands on the remote node
uninstall_kubernetes() {
    local ip=$1
    local node_type=$2
    print_header "Uninstalling Kubernetes from $node_type node $ip"
    
    run_ssh_command "$ip" "
        echo 'Stopping kubelet service...'
        systemctl stop kubelet

        echo 'Removing Kubernetes components...'
        if [ '$node_type' = 'master' ]; then
            # Reset control plane
            kubeadm reset --force
            
            # Remove Calico resources if this is the master
            kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml || true
            kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml || true
        else
            # Worker node reset
            kubeadm reset --force
        fi

        # Deleting network interfaces
        for iface in \$(ip -o link show | awk -F': ' '/^[0-9]+: (cali|vxlan|flannel|docker)/ {print \$2}' | cut -d'@' -f1); do
            ip link delete \"\$iface\" || true
        done

        echo 'Removing Kubernetes packages...'
        apt-mark unhold kubelet kubeadm kubectl
        apt purge -y kubeadm kubectl kubelet kubernetes-cni
        
        echo 'Removing Docker and containerd...'
        systemctl stop docker || true
        systemctl stop containerd || true
        apt purge -y docker-ce docker-ce-cli containerd.io docker docker-engine docker.io containerd runc
        
        echo 'Removing configurations and directories...'
        # Kubernetes directories
        rm -rf /etc/kubernetes/
        rm -rf /var/lib/kubernetes/
        rm -rf /var/lib/etcd/
        rm -rf /var/lib/kubelet/
        rm -rf /etc/cni/
        rm -rf /var/lib/cni/
        rm -rf /var/run/kubernetes/
        rm -rf /opt/cni/
        rm -rf /var/log/containers/
        rm -rf /var/log/pods/
        rm -rf ~/.kube
        
        # Docker directories
        rm -rf /var/lib/docker/
        rm -rf /etc/docker
        rm -rf /var/run/docker.sock
        
        echo 'Removing systemd services...'
        rm -f /etc/systemd/system/kubelet.service
        rm -f /etc/systemd/system/docker.service
        rm -rf /etc/systemd/system/kubelet.service.d/
        rm -rf /etc/systemd/system/docker.service.d/
        systemctl daemon-reload
        
        echo 'Cleaning package management...'
        apt autoremove -y
        apt clean
        
        echo 'Removing repositories...'
        rm -f /etc/apt/sources.list.d/kubernetes.list
        rm -f /etc/apt/sources.list.d/docker.list
        rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        rm -f /etc/apt/keyrings/docker-archive-keyring.gpg
        
        echo 'Resetting network configurations...'
        # Remove CNI configurations
        ip link delete cni0 || true
        ip link delete flannel.1 || true
        ip link delete calico.1 || true
        
        # Clean up iptables
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        
        echo 'Resetting hostname...'
        hostnamectl set-hostname \$(cat /etc/hostname.original || echo 'localhost')
        
        echo 'Updating hosts file...'
        sed -i '/k8s/d' /etc/hosts
        
        echo 'Node cleanup complete.'
    "
    check_success "Failed to uninstall Kubernetes from node $ip"
}


# Function: perform_uninstall
# Description: Orchestrates the uninstallation of Kubernetes from all nodes
# Arguments: None
# Output: None, but coordinates the uninstall process
perform_uninstall() {
    print_header "Starting Kubernetes Cluster Uninstallation"
    
    # Backup current hostname on all nodes
    for worker_ip in "${WORKER_IPS[@]}"; do
        run_ssh_command "$worker_ip" "cp /etc/hostname /etc/hostname.original || true"
    done
    run_ssh_command "$MASTER_IP" "cp /etc/hostname /etc/hostname.original || true"
    
    # Uninstall from worker nodes first
    local worker_index=1
    for worker_ip in "${WORKER_IPS[@]}"; do
        print_header "Uninstalling worker node $worker_index: $worker_ip"
        uninstall_kubernetes "$worker_ip" "worker"
        ((worker_index++))
    done
    
    # Uninstall from master node last
    print_header "Uninstalling master node: $MASTER_IP"
    uninstall_kubernetes "$MASTER_IP" "master"
    
    # Clean up local kubeconfig if it exists
    if [ -f "$HOME/.kube/config" ]; then
        print_header "Cleaning up local kubeconfig"
        rm -rf "$HOME/.kube"
        echo "Local kubeconfig removed"
    fi
    
    print_header "Kubernetes Cluster Uninstallation Complete"
    echo "All nodes have been reset to their original state."
    echo "You may need to reboot the nodes to ensure all changes take effect."
}


# Function: run_ssh_command
# Description: Executes a command on a remote node via SSH using either key or password.
# Arguments:
#   $1 - IP address of the target node
#   $2 - Command to execute
# Output: The output of the executed command
run_ssh_command() {
    local ip=$1
    local command=$2
    if [ "$USE_SSH_KEY" = true ]; then
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$SSH_USER@$ip" "$command"
    else
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ip" "$command"
    fi
}


# Function: check_success
# Description: Checks if the previous command was successful, exits the script if not.
# Arguments:
#   $1 - Error message to display if the check fails
# Output: Prints error message to stderr and exits if the previous command failed
check_success() {
    if [ $? -ne 0 ]; then
        echo "Error: $1" >&2
        exit 1
    fi
}


# Function: set_hostname
# Description: Sets a unique hostname for each node
# Arguments:
#   $1 - IP address of the node
#   $2 - Node type (master/worker)
#   $3 - Node index (for workers)
# Output: None
set_hostname() {
    local ip=$1
    local node_type=$2
    local index=$3
    local hostname=""
    
    if [ "$node_type" = "master" ]; then
        hostname="vsaas-masternode"
    else
        hostname="vsaas-workernode-$index"
    fi
    
    print_header "Setting hostname to $hostname on node $ip"
    
    run_ssh_command "$ip" "
        # First update /etc/hosts
        echo '127.0.0.1 localhost' > /etc/hosts
        echo '$ip $hostname' >> /etc/hosts
        
        # Then set the hostname
        hostnamectl set-hostname $hostname --static
        
        # Update hostname immediately without requiring reboot
        hostname $hostname
        
        # Verify the hostname is set correctly
        echo 'New hostname:' && hostname -f
        echo 'Hosts file:' && cat /etc/hosts
    "
    check_success "Failed to set hostname on node $ip"
}


# Function: prepare_node
# Description: Prepares a node for Kubernetes installation by installing dependencies,
#              configuring the system, and setting up Docker and containerd.
# Arguments:
#   $1 - IP address of the node to prepare
#   $2 - Node type (master/worker)
#   $3 - Node index (for workers)
# Output: None, but executes multiple commands on the remote node
prepare_node() {
    local ip=$1
    local node_type=$2
    local index=$3
    print_header "Preparing node $ip"

    run_ssh_command "$ip" "
        # Disable swap
        swapoff -a
        sed -i '/ swap / s/^\\(.*\\)$/#\\1/g' /etc/fstab
        
        # Load kernel modules
        cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
        modprobe overlay
        modprobe br_netfilter

        # Set system configurations
        cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
        sysctl --system

        # Clean up any existing installations
        systemctl stop kubelet containerd docker || true
        systemctl disable kubelet containerd docker || true
        rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /usr/bin/kube* /etc/cni /opt/cni
        rm -f /etc/systemd/system/kubelet.service
        rm -rf /etc/systemd/system/kubelet.service.d

        # Install Docker and containerd
        apt-get remove -y docker docker-engine docker.io containerd runc || true
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

        # Add Docker's official GPG key
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Add Docker repository
        echo \
          \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker and containerd
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io

        # Configure containerd
        mkdir -p /etc/containerd
        containerd config default | tee /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

        # Configure Docker
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
    \"exec-opts\": [\"native.cgroupdriver=systemd\"],
    \"log-driver\": \"json-file\",
    \"log-opts\": {
        \"max-size\": \"100m\"
    },
    \"storage-driver\": \"overlay2\"
}
EOF

        # Create necessary directories
        mkdir -p /usr/bin
        mkdir -p /etc/kubernetes/manifests
        mkdir -p /var/lib/kubelet
        mkdir -p /var/lib/etcd
        mkdir -p /opt/cni/bin
        mkdir -p /etc/cni/net.d
        
        # Download CNI plugins
        curl -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz | tar -xz -C /opt/cni/bin

        # Download Kubernetes binaries
        cd /usr/bin
        curl -L --remote-name-all https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
        chmod +x {kubeadm,kubelet,kubectl}

        # Restart services
        systemctl daemon-reload
        systemctl restart containerd
        systemctl restart docker
        systemctl enable containerd
        systemctl enable docker

        # Create kubelet service
        cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target containerd.service
After=network-online.target containerd.service

[Service]
ExecStart=/usr/bin/kubelet \\
    --container-runtime=remote \\
    --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
    --pod-manifest-path=/etc/kubernetes/manifests \\
    --kubeconfig=/etc/kubernetes/kubelet.conf \\
    --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \\
    --config=/var/lib/kubelet/config.yaml \\
    --cgroup-driver=systemd \\
    --network-plugin=cni \\
    --cni-conf-dir=/etc/cni/net.d \\
    --cni-bin-dir=/opt/cni/bin \\
    --v=2
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        mkdir -p /etc/systemd/system/kubelet.service.d
        cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
Environment=\"KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf\"
Environment=\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\"
Environment=\"KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests\"
Environment=\"KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin\"
Environment=\"KUBELET_EXTRA_ARGS=--container-runtime=remote --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock\"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_SYSTEM_PODS_ARGS \$KUBELET_NETWORK_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF

        cat > /var/lib/kubelet/config.yaml <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
protectKernelDefaults: true
EOF

        # Set permissions
        chmod 644 /etc/systemd/system/kubelet.service
        chmod 644 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
        chmod 644 /var/lib/kubelet/config.yaml

        # Reload and start services
        systemctl daemon-reload
        systemctl enable kubelet
        systemctl start kubelet

        # Verify installations
        echo 'Verifying installations...'
        docker --version
        containerd --version
        kubelet --version
        kubeadm version
        kubectl version --client
        
        echo 'Service Status:'
        systemctl status containerd --no-pager || true
        systemctl status docker --no-pager || true
        systemctl status kubelet --no-pager || true
    "
    check_success "Failed to prepare node $ip"
}


# Function: init_master
# Description: Initializes the Kubernetes master node, sets up kubectl, and installs the Calico network plugin.
# Arguments: None
# Output: None, but executes multiple commands on the master node
init_master() {
    print_header "Initializing master node"
    
    run_ssh_command "$MASTER_IP" "
        # Verify kubeadm is installed
        if ! command -v kubeadm &> /dev/null; then
            echo 'Error: kubeadm not found. Installation may have failed.'
            exit 1
        fi

        # Initialize kubeadm
        kubeadm init --pod-network-cidr=$POD_CIDR --apiserver-advertise-address=$MASTER_IP

        # Set up kubeconfig
        mkdir -p \$HOME/.kube
        cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config
        chown \$(id -u):\$(id -g) \$HOME/.kube/config

        # Wait for control-plane components
        echo 'Waiting for control-plane components to be ready...'
        sleep 30

        # Install Calico network plugin
        kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml
        kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml

        # Wait for pods to be ready
        echo 'Waiting for system pods to be ready...'
        kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

        # Remove master node taint if needed
        kubectl taint nodes --all node-role.kubernetes.io/control-plane-

        # Show cluster status
        echo 'Cluster status:'
        kubectl get nodes
        kubectl get pods --all-namespaces
    "
    check_success "Failed to initialize master node"
}


# Function: get_join_command
# Description: Retrieves the kubeadm join command from the master node to be used by worker nodes.
# Arguments: None
# Output: Sets the JOIN_COMMAND global variable with the join command string
get_join_command() {
    print_header "Getting join command from master"
    
    JOIN_COMMAND=$(run_ssh_command "$MASTER_IP" "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        kubeadm token create --print-join-command
    ")
    check_success "Failed to get join command"
}


# Function: join_workers
# Description: Joins all worker nodes to the Kubernetes cluster using the join command.
# Arguments: None
# Output: None, but executes the join command on all worker nodes
join_workers() {
    local worker_index=1
    for worker_ip in "${WORKER_IPS[@]}"; do
        print_header "Joining worker node $worker_ip (k8s-worker-$worker_index)"
        
        run_ssh_command "$worker_ip" "
            # Execute join command
            $JOIN_COMMAND

            # Verify kubelet is running
            systemctl status kubelet
        "
        check_success "Failed to join worker node $worker_ip"
        
        ((worker_index++))
    done
}


# Function: verify_cluster
# Description: Verifies the Kubernetes cluster setup by checking node and pod status.
# Arguments: None
# Output: Prints the output of 'kubectl get nodes' and 'kubectl get pods --all-namespaces'
verify_cluster() {
    print_header "Verifying cluster setup"
    
    run_ssh_command "$MASTER_IP" "
        # Set KUBECONFIG environment variable
        export KUBECONFIG=/etc/kubernetes/admin.conf

        # Wait for all nodes to be ready
        echo 'Waiting for all nodes to become ready...'
        kubectl wait --for=condition=Ready nodes --all --timeout=300s

        # Check node status
        echo 'Node Status:'
        kubectl get nodes -o wide
        
        # Check pod status
        echo 'Pod Status:'
        kubectl get pods --all-namespaces
        
        # Check cluster info
        echo 'Cluster Info:'
        kubectl cluster-info
        
        # Check component status
        echo 'Component Status:'
        kubectl get componentstatuses || true
    "
    check_success "Cluster verification failed"
}


# Add this new function to save the kubeconfig file locally
# Function: save_kubeconfig
# Description: Saves the kubeconfig file from the master node to the local machine
# Arguments: None
# Output: None, creates a local kubeconfig file
save_kubeconfig() {
    print_header "Saving kubeconfig file locally"
    
    # Create local .kube directory if it doesn't exist
    mkdir -p $HOME/.kube
    
    # Use sshpass with password or regular scp with key
    if [ "$USE_SSH_KEY" = true ]; then
        scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" $SSH_USER@$MASTER_IP:/etc/kubernetes/admin.conf $HOME/.kube/config
    else
        sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no $SSH_USER@$MASTER_IP:/etc/kubernetes/admin.conf $HOME/.kube/config
    fi
    
    # Set proper ownership
    chmod 600 $HOME/.kube/config
    
    echo "Kubeconfig has been saved to $HOME/.kube/config"
}

verify_installation() {
    local ip=$1
    print_header "Verifying installation on node $ip"
    
    run_ssh_command "$ip" "
        # Check if required commands exist
        for cmd in docker containerd kubeadm kubectl kubelet; do
            if ! command -v \$cmd &> /dev/null; then
                echo \"Error: \$cmd is not installed\"
                exit 1
            fi
        done
        
        # Check service status
        systemctl is-active --quiet containerd || (echo 'containerd is not running' && exit 1)
        systemctl is-active --quiet docker || (echo 'docker is not running' && exit 1)
        systemctl is-active --quiet kubelet || (echo 'kubelet is not running' && exit 1)
        
        echo 'All required components are installed and running'
    "
    check_success "Installation verification failed on node $ip"
}


# Function: main
# Description: The main function that orchestrates the entire process
# Arguments: All command line arguments ($@)
# Output: None, but coordinates the entire installation or uninstallation process
main() {
    print_header "Kubernetes Cluster Management Script"
    
    parse_arguments "$@"
    check_prerequisites
    
    if [ "$UNINSTALL" = true ]; then
        perform_uninstall
        
        # Clean up any remaining environment variables
        unset KUBECONFIG
        
        echo "Recommendation: Please reboot all nodes to ensure complete cleanup."
        exit 0
    fi
    
    print_header "Starting Kubernetes Cluster Installation"
    
    print_header "Preparing Nodes"
    prepare_node "$MASTER_IP" "master" 0
    verify_installation "$MASTER_IP"
    
    local worker_index=1
    for worker_ip in "${WORKER_IPS[@]}"; do
        prepare_node "$worker_ip" "worker" "$worker_index"
        verify_installation "$worker_ip"
        ((worker_index++))
    done
    
    print_header "Initializing Master Node"
    init_master
    
    print_header "Getting Join Command"
    get_join_command
    
    print_header "Joining Worker Nodes"
    join_workers

    print_header "Saving Cluster Configuration"
    save_kubeconfig
    
    print_header "Verifying Cluster"
    verify_cluster

    print_header "Kubernetes Cluster Setup Complete!"
    echo "You can now use kubectl commands locally to manage your cluster."
    echo "Try 'kubectl get nodes' to verify access."
    
    # Verify local access
    if command -v kubectl &> /dev/null; then
        echo "Testing local kubectl access:"
        kubectl get nodes
    else
        echo "Note: Install kubectl locally to manage your cluster"
    fi
    
    #print_header "Kubernetes Cluster Setup Complete!"
    
    # Print cluster access information
    print_header "Cluster Access Information"
    echo "To access the cluster from your local machine:"
    echo "1. Install kubectl locally"
    echo "2. Get the kubeconfig file from master node:"
    echo "   scp $SSH_USER@$MASTER_IP:/etc/kubernetes/admin.conf ~/.kube/config"
    echo "3. Test access with:"
    echo "   kubectl get nodes"
}

# Run the main function
main "$@"