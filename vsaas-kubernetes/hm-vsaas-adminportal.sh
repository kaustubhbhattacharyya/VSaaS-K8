NAMESPACE="vsaas-dev"
RELEASE_NAME="vsaas-adminportal"
CHART_PATH="./vsaas-adminportal"
VALUES_FILE="./vsaas-adminportal/values.yaml"
TIMEOUT="5m"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 


usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo
    echo "Commands:"
    echo "  install     Install the Helm chart"
    echo "  uninstall   Uninstall the Helm chart"
    echo "  upgrade     Upgrade the Helm chart"
    echo "  rollback    Rollback to previous release"
    echo "  status      Check the status of the release"
    echo "  template    Template the chart and display output"
    echo "  lint        Lint the chart"
    echo
    echo "Options:"
    echo "  -n, --namespace NAMESPACE    Specify Kubernetes namespace (default: vsaas-dev)"
    echo "  -r, --release RELEASE_NAME   Specify release name (default: vsaas-adminportal)"
    echo "  -f, --values VALUES_FILE     Specify values file (default: values.yaml)"
    echo "  -t, --timeout TIMEOUT        Specify timeout duration (default: 5m)"
    echo "  -h, --help                   Display this help message"
}


check_helm() {
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Error: helm is not installed${NC}"
        exit 1
    fi
}


check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${YELLOW}Namespace $NAMESPACE does not exist. Creating it...${NC}"
        kubectl create namespace "$NAMESPACE"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Namespace $NAMESPACE created successfully${NC}"
        else
            echo -e "${RED}Failed to create namespace $NAMESPACE${NC}"
            exit 1
        fi
    fi
}


validate_chart() {
    if [ ! -d "$CHART_PATH" ]; then
        echo -e "${RED}Error: Chart directory $CHART_PATH does not exist${NC}"
        exit 1
    fi
}


while [[ $
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        install|uninstall|upgrade|rollback|status|template|lint)
            COMMAND="$1"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            exit 1
            ;;
    esac
done


if [ -z "$COMMAND" ]; then
    echo -e "${RED}Error: No command specified${NC}"
    usage
    exit 1
fi


check_helm

case $COMMAND in
    install)
        echo -e "${YELLOW}Installing $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        check_namespace
        validate_chart
        helm install "$RELEASE_NAME" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --timeout "$TIMEOUT" \
            --create-namespace
        ;;
        
    uninstall)
        echo -e "${YELLOW}Uninstalling $RELEASE_NAME from namespace $NAMESPACE...${NC}"
        helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
        ;;
        
    upgrade)
        echo -e "${YELLOW}Upgrading $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        validate_chart
        helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --timeout "$TIMEOUT" \
            --install
        ;;
        
    rollback)
        echo -e "${YELLOW}Rolling back $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        helm rollback "$RELEASE_NAME" --namespace "$NAMESPACE"
        ;;
        
    status)
        echo -e "${YELLOW}Checking status of $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        helm status "$RELEASE_NAME" --namespace "$NAMESPACE"
        ;;
        
    template)
        echo -e "${YELLOW}Templating chart for $RELEASE_NAME in namespace $NAMESPACE...${NC}"
        validate_chart
        helm template "$RELEASE_NAME" "$CHART_PATH" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE"
        ;;
        
    lint)
        echo -e "${YELLOW}Linting chart...${NC}"
        validate_chart
        helm lint "$CHART_PATH" --namespace "$NAMESPACE" --values "$VALUES_FILE"
        ;;
esac


if [ $? -eq 0 ]; then
    echo -e "${GREEN}Command completed successfully${NC}"
else
    echo -e "${RED}Command failed${NC}"
    exit 1
fi