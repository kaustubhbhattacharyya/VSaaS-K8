


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' 


print_banner() {
    echo -e "${BLUE}"
    echo '██╗   ██╗███████╗ █████╗  █████╗ ███████╗    ███╗   ███╗███████╗████████╗ █████╗ ██╗     ██╗     ██████╗'
    echo '██║   ██║██╔════╝██╔══██╗██╔══██╗██╔════╝    ████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔══██╗'
    echo '██║   ██║███████╗███████║███████║███████╗    ██╔████╔██║█████╗     ██║   ███████║██║     ██║     ██████╔╝'
    echo '╚██╗ ██╔╝╚════██║██╔══██║██╔══██║╚════██║    ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║     ██║     ██╔══██╗'
    echo ' ╚████╔╝ ███████║██║  ██║██║  ██║███████║    ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗███████╗██████╔╝'
    echo '  ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝    ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝'
    echo -e "${NC}"
    echo -e "${CYAN}VSaaS MetalLB Installation Script${NC}"
    echo -e "${CYAN}================================${NC}\n"
}


show_help() {
    echo -e "${GREEN}Usage:${NC}"
    echo -e "  $0 [command] [options]\n"
    echo -e "${GREEN}Commands:${NC}"
    echo -e "  install   ${YELLOW}Install MetalLB with specified public IP${NC}"
    echo -e "  uninstall ${YELLOW}Uninstall MetalLB and clean up resources${NC}"
    echo -e "  help      ${YELLOW}Show this help message${NC}\n"
    echo -e "${GREEN}Options:${NC}"
    echo -e "  -ip       ${YELLOW}Public IP address for MetalLB (required for install)${NC}"
    echo -e "\n${GREEN}Examples:${NC}"
    echo -e "  $0 install -ip 172.235.26.240"
    echo -e "  $0 uninstall"
    echo -e "  $0 help\n"
}


validate_ip() {
    if [[ ! $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Invalid IP address format${NC}"
        exit 1
    fi
}


check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        echo -e "${RED}helm not found. Please install helm first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Prerequisites check passed${NC}"
}


install_metallb() {
    local PUBLIC_IP=$1
    
    echo -e "${YELLOW}Starting MetalLB installation...${NC}"
    
    
    validate_ip "$PUBLIC_IP"
    
    
    echo -e "${YELLOW}Cleaning up existing installation...${NC}"
    helm uninstall metallb -n metallb-system 2>/dev/null || true
    kubectl delete namespace metallb-system 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration 2>/dev/null || true
    kubectl delete crd bfdprofiles.metallb.io bgppeers.metallb.io ipaddresspools.metallb.io l2advertisements.metallb.io 2>/dev/null || true
    sleep 10
    
    
    echo -e "${YELLOW}Adding MetalLB Helm repository...${NC}"
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    
    
    echo -e "${YELLOW}Creating metallb-system namespace...${NC}"
    kubectl create namespace metallb-system
    
    
    echo -e "${YELLOW}Installing MetalLB...${NC}"
    helm install metallb metallb/metallb -n metallb-system
    
    
    echo -e "${YELLOW}Creating MetalLB configuration...${NC}"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${PUBLIC_IP}/32
EOF
    
    
    echo -e "${YELLOW}Verifying installation...${NC}"
    kubectl get pods -n metallb-system
    
    echo -e "${GREEN}MetalLB installation completed successfully!${NC}"
}


uninstall_metallb() {
    echo -e "${YELLOW}Uninstalling MetalLB...${NC}"
    
    helm uninstall metallb -n metallb-system 2>/dev/null || true
    kubectl delete namespace metallb-system 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration 2>/dev/null || true
    kubectl delete crd bfdprofiles.metallb.io bgppeers.metallb.io ipaddresspools.metallb.io l2advertisements.metallb.io 2>/dev/null || true
    
    echo -e "${GREEN}MetalLB uninstalled successfully!${NC}"
}


main() {
    print_banner
    check_prerequisites
    
    case "$1" in
        install)
            if [ "$2" != "-ip" ] || [ -z "$3" ]; then
                echo -e "${RED}Error: IP address required for installation${NC}"
                show_help
                exit 1
            fi
            install_metallb "$3"
            ;;
        uninstall)
            uninstall_metallb
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Invalid command${NC}"
            show_help
            exit 1
            ;;
    esac
}


main "$@"