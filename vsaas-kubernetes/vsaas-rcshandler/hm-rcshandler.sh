CHART_NAME="vsaas-rcshandler"
NAMESPACE="vsaas-dev"
CHART_PATH="./vsaas-rcshandler"
VALUES_FILE="values.yaml"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 


usage() {
    echo -e "${YELLOW}Usage:${NC} $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  install         Install the RCS Handler chart"
    echo "  uninstall      Uninstall the RCS Handler release"
    echo "  upgrade        Upgrade the RCS Handler release"
    echo "  rollback       Rollback to a previous release version"
    echo "  status         Check the status of the release"
    echo "  template       View the rendered templates"
    echo "  lint           Lint the chart"
    echo "  list           List all releases in the namespace"
    echo
    echo "Options:"
    echo "  -n, --namespace    Specify a different namespace (default: vsaas-dev)"
    echo "  -f, --values       Specify values file (default: values.yaml)"
    echo "  -v, --version      Specify version for rollback"
    echo
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 upgrade -f custom-values.yaml"
    echo "  $0 rollback -v 1"
    echo "  $0 install -n custom-namespace"
}


check_helm() {
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Error: helm is not installed${NC}"
        exit 1
    fi
}


ensure_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${YELLOW}Namespace $NAMESPACE does not exist. Creating...${NC}"
        kubectl create namespace "$NAMESPACE"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Namespace $NAMESPACE created successfully${NC}"
        else
            echo -e "${RED}Failed to create namespace $NAMESPACE${NC}"
            exit 1
        fi
    fi
}


check_chart() {
    if [ ! -d "$CHART_PATH" ]; then
        echo -e "${RED}Error: Chart directory $CHART_PATH not found${NC}"
        exit 1
    fi
}


pre_flight_checks() {
    check_helm
    check_chart
    ensure_namespace
}


handle_error() {
    local exit_code=$1
    local operation=$2
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}Error: $operation failed${NC}"
        exit $exit_code
    fi
}


do_install() {
    echo -e "${YELLOW}Installing $CHART_NAME in namespace $NAMESPACE...${NC}"
    helm install $CHART_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --values $VALUES_FILE \
        --create-namespace
    handle_error $? "Installation"
    echo -e "${GREEN}Installation completed successfully${NC}"
}


do_uninstall() {
    echo -e "${YELLOW}Uninstalling $CHART_NAME from namespace $NAMESPACE...${NC}"
    helm uninstall $CHART_NAME --namespace $NAMESPACE
    handle_error $? "Uninstallation"
    echo -e "${GREEN}Uninstallation completed successfully${NC}"
}


do_upgrade() {
    echo -e "${YELLOW}Upgrading $CHART_NAME in namespace $NAMESPACE...${NC}"
    helm upgrade $CHART_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --values $VALUES_FILE \
        --atomic
    handle_error $? "Upgrade"
    echo -e "${GREEN}Upgrade completed successfully${NC}"
}


do_rollback() {
    if [ -z "$VERSION" ]; then
        echo -e "${RED}Error: Version number required for rollback${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Rolling back $CHART_NAME to version $VERSION in namespace $NAMESPACE...${NC}"
    helm rollback $CHART_NAME $VERSION --namespace $NAMESPACE
    handle_error $? "Rollback"
    echo -e "${GREEN}Rollback completed successfully${NC}"
}


do_status() {
    echo -e "${YELLOW}Checking status of $CHART_NAME in namespace $NAMESPACE...${NC}"
    helm status $CHART_NAME --namespace $NAMESPACE
    kubectl get all -n $NAMESPACE -l app.kubernetes.io/instance=$CHART_NAME
}


do_template() {
    echo -e "${YELLOW}Rendering templates for $CHART_NAME...${NC}"
    helm template $CHART_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --values $VALUES_FILE
}


do_lint() {
    echo -e "${YELLOW}Linting $CHART_NAME...${NC}"
    helm lint $CHART_PATH --values $VALUES_FILE
    handle_error $? "Lint"
    echo -e "${GREEN}Lint completed successfully${NC}"
}


do_list() {
    echo -e "${YELLOW}Listing all releases in namespace $NAMESPACE...${NC}"
    helm list --namespace $NAMESPACE
}


COMMAND=$1
shift

while [[ $
    key="$1"
    case $key in
        -n|--namespace)
            NAMESPACE="$2"
            shift
            shift
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift
            shift
            ;;
        -v|--version)
            VERSION="$2"
            shift
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done


case $COMMAND in
    install)
        pre_flight_checks
        do_install
        ;;
    uninstall)
        pre_flight_checks
        do_uninstall
        ;;
    upgrade)
        pre_flight_checks
        do_upgrade
        ;;
    rollback)
        pre_flight_checks
        do_rollback
        ;;
    status)
        pre_flight_checks
        do_status
        ;;
    template)
        pre_flight_checks
        do_template
        ;;
    lint)
        pre_flight_checks
        do_lint
        ;;
    list)
        pre_flight_checks
        do_list
        ;;
    *)
        echo -e "${RED}Invalid command: $COMMAND${NC}"
        usage
        exit 1
        ;;
esac