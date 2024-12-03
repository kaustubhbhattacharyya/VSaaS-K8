RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 


CHART_NAME="vsaas-mqtt"
CHART_PATH="./vsaas-mqtt"
DEFAULT_ENV="dev"
DEFAULT_VERSION="0.1.0"


usage() {
    echo -e "${YELLOW}Usage: $0 [operation] [environment] [version]${NC}"
    echo -e "\nOperations:"
    echo "  install     - Install the Helm chart"
    echo "  uninstall   - Uninstall the Helm chart"
    echo "  upgrade     - Upgrade the Helm chart"
    echo "  rollback    - Rollback to previous version"
    echo "  status      - Check deployment status"
    echo "  lint        - Lint the chart"
    echo -e "\nEnvironments:"
    echo "  dev        - Development environment"
    echo "  staging    - Staging environment"
    echo "  prod       - Production environment"
    echo -e "\nExample:"
    echo "  $0 install dev 1.0.0"
    exit 1
}


validate_environment() {
    case $1 in
        dev|staging|prod) return 0 ;;
        *) echo -e "${RED}Invalid environment. Use dev, staging, or prod${NC}" && exit 1 ;;
    esac
}


validate_version() {
    if ! [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Invalid version format. Use semantic versioning (e.g., 1.0.0)${NC}"
        exit 1
    fi
}


ensure_namespace() {
    local namespace="vsaas-$1"
    if ! kubectl get namespace $namespace >/dev/null 2>&1; then
        echo -e "${YELLOW}Namespace $namespace does not exist. Creating...${NC}"
        kubectl create namespace $namespace
    fi
}


check_helm() {
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Helm is not installed. Please install Helm first.${NC}"
        exit 1
    fi
}


get_values_file() {
    local env=$1
    if [ -f "$CHART_PATH/values-$env.yaml" ]; then
        echo "$CHART_PATH/values-$env.yaml"
    else
        echo "$CHART_PATH/values.yaml"
    fi
}


perform_helm_operation() {
    local operation=$1
    local environment=$2
    local version=$3
    local namespace="vsaas-$environment"
    local values_file=$(get_values_file $environment)
    local release_name="$CHART_NAME-$environment"

    ensure_namespace $environment

    case $operation in
        install)
            echo -e "${GREEN}Installing $CHART_NAME in $namespace namespace...${NC}"
            helm install $release_name $CHART_PATH \
                --namespace $namespace \
                --values $values_file \
                --set image.tag=$version
            ;;
        uninstall)
            echo -e "${YELLOW}Uninstalling $CHART_NAME from $namespace namespace...${NC}"
            helm uninstall $release_name --namespace $namespace
            ;;
        upgrade)
            echo -e "${GREEN}Upgrading $CHART_NAME in $namespace namespace...${NC}"
            helm upgrade $release_name $CHART_PATH \
                --namespace $namespace \
                --values $values_file \
                --set image.tag=$version
            ;;
        rollback)
            echo -e "${YELLOW}Rolling back $CHART_NAME in $namespace namespace...${NC}"
            helm rollback $release_name --namespace $namespace
            ;;
        status)
            echo -e "${GREEN}Checking status of $CHART_NAME in $namespace namespace...${NC}"
            helm status $release_name --namespace $namespace
            kubectl get all -n $namespace -l app.kubernetes.io/instance=$release_name
            ;;
        lint)
            echo -e "${GREEN}Linting $CHART_NAME chart...${NC}"
            helm lint $CHART_PATH --values $values_file
            ;;
        *)
            usage
            ;;
    esac
}


main() {
    
    check_helm

    
    OPERATION=$1
    ENVIRONMENT=${2:-$DEFAULT_ENV}
    VERSION=${3:-$DEFAULT_VERSION}

    
    if [ -z "$OPERATION" ]; then
        usage
    fi

    validate_environment $ENVIRONMENT
    validate_version $VERSION

    
    perform_helm_operation $OPERATION $ENVIRONMENT $VERSION

    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Operation completed successfully!${NC}"
    else
        echo -e "${RED}Operation failed!${NC}"
        exit 1
    fi
}


main "$@"