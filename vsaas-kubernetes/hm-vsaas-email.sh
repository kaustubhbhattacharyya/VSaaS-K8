DEFAULT_NAMESPACE="vsaas-dev"
CHART_NAME="vsaas-email"
RELEASE_NAME="vsaas-email"
DEFAULT_VERSION="0.1.0"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 


usage() {
    echo -e "${YELLOW}Usage: $0 [operation] [environment] [version]${NC}"
    echo "Operations:"
    echo "  install     - Install the Helm chart"
    echo "  uninstall   - Uninstall the Helm release"
    echo "  upgrade     - Upgrade the Helm release"
    echo "  rollback    - Rollback to the previous release"
    echo "  status      - Check the status of the release"
    echo "  lint        - Lint the Helm chart"
    echo "  template    - Template the chart (dry-run)"
    echo -e "Environments:"
    echo "  dev        - Development environment"
    echo "  staging    - Staging environment"
    echo "  prod       - Production environment"
    echo -e "Version: Optional - defaults to ${DEFAULT_VERSION}"
    exit 1
}


validate_environment() {
    case $1 in
        dev)
            NAMESPACE="${DEFAULT_NAMESPACE}"
            VALUES_FILE="values-dev.yaml"
            ;;
        staging)
            NAMESPACE="vsaas-staging"
            VALUES_FILE="values-staging.yaml"
            ;;
        prod)
            NAMESPACE="vsaas-prod"
            VALUES_FILE="values-prod.yaml"
            ;;
        *)
            echo -e "${RED}Invalid environment. Please use dev, staging, or prod${NC}"
            usage
            ;;
    esac
}


ensure_namespace() {
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}Namespace $NAMESPACE does not exist. Creating it...${NC}"
        kubectl create namespace $NAMESPACE
    fi
}


check_chart_exists() {
    if [ ! -d "$CHART_NAME" ]; then
        echo -e "${RED}Error: Chart directory '$CHART_NAME' not found${NC}"
        exit 1
    fi
}


check_helm() {
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Error: Helm is not installed${NC}"
        exit 1
    fi
}


add_helm_repos() {
    
    
    helm repo update
}


if [ $
    usage
fi


OPERATION=$1
ENVIRONMENT=$2
VERSION=${3:-$DEFAULT_VERSION}


validate_environment $ENVIRONMENT
check_helm
check_chart_exists


case $OPERATION in
    install)
        ensure_namespace
        echo -e "${GREEN}Installing $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        helm install $RELEASE_NAME ./$CHART_NAME \
            --namespace $NAMESPACE \
            --values $CHART_NAME/$VALUES_FILE \
            --version $VERSION
        ;;
    
    uninstall)
        echo -e "${YELLOW}Uninstalling $RELEASE_NAME from namespace $NAMESPACE...${NC}"
        helm uninstall $RELEASE_NAME --namespace $NAMESPACE
        ;;
    
    upgrade)
        ensure_namespace
        echo -e "${GREEN}Upgrading $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        helm upgrade $RELEASE_NAME ./$CHART_NAME \
            --namespace $NAMESPACE \
            --values $CHART_NAME/$VALUES_FILE \
            --version $VERSION
        ;;
    
    rollback)
        echo -e "${YELLOW}Rolling back $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        helm rollback $RELEASE_NAME --namespace $NAMESPACE
        ;;
    
    status)
        echo -e "${GREEN}Checking status of $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        helm status $RELEASE_NAME --namespace $NAMESPACE
        ;;
    
    lint)
        echo -e "${GREEN}Linting chart $CHART_NAME...${NC}"
        helm lint ./$CHART_NAME --values $CHART_NAME/$VALUES_FILE
        ;;
    
    template)
        echo -e "${GREEN}Templating chart $CHART_NAME...${NC}"
        helm template $RELEASE_NAME ./$CHART_NAME \
            --namespace $NAMESPACE \
            --values $CHART_NAME/$VALUES_FILE \
            --version $VERSION
        ;;
    
    *)
        echo -e "${RED}Invalid operation${NC}"
        usage
        ;;
esac


if [[ $OPERATION == "install" || $OPERATION == "upgrade" ]]; then
    echo -e "\n${GREEN}Checking pod status...${NC}"
    kubectl get pods -n $NAMESPACE | grep $RELEASE_NAME
fi

exit 0