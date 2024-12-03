GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENVIRONMENT="dev"
NAMESPACE="vsaas-dev"
RELEASE_NAME="nginx-ingress-ingress"
CHART_PATH="./vsaas-nginx-ingress"

log() {
    local level=$1
    shift
    local message=$@
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${level}] ${timestamp} - ${message}"
}


check_values_file() {
    local env_values="${CHART_PATH}/values-${ENVIRONMENT}.yaml"
    if [ ! -f "$env_values" ]; then
        log "ERROR" "Values file not found: $env_values"
        exit 1
    fi
}

while [[ $
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done


if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    log "ERROR" "Invalid environment. Must be one of: dev, staging, prod"
    exit 1
fi


check_values_file


log "INFO" "Creating namespace: $NAMESPACE"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -


log "INFO" "Testing template rendering..."
helm template ${RELEASE_NAME} ${CHART_PATH} \
    --namespace ${NAMESPACE} \
    -f ${CHART_PATH}/values.yaml \
    -f ${CHART_PATH}/values-${ENVIRONMENT}.yaml \
    --debug > /tmp/ingress-templates.yaml

if [ $? -ne 0 ]; then
    log "ERROR" "Template rendering failed"
    exit 1
fi


log "INFO" "Deploying to ${ENVIRONMENT} environment..."
if ! helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
    --namespace ${NAMESPACE} \
    -f ${CHART_PATH}/values.yaml \
    -f ${CHART_PATH}/values-${ENVIRONMENT}.yaml \
    --create-namespace \
    --atomic \
    --timeout 5m0s; then
    log "ERROR" "Deployment failed"
    exit 1
fi


log "INFO" "Waiting for ingress resources to be ready..."
sleep 10  


echo -e "\n${GREEN}=== Ingress Resources ===${NC}"
kubectl get ingress -n ${NAMESPACE}


echo -e "\n${GREEN}=== Ingress Controller Status ===${NC}"
kubectl get pods -n ingress-nginx


INGRESS_IP=$(kubectl get svc ingress-nginx -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ ! -z "$INGRESS_IP" ]; then
    echo -e "\n${GREEN}=== Access Information ===${NC}"
    echo "Ingress IP: $INGRESS_IP"
    echo -e "To test: curl -H 'Host: ${DOMAIN}' http://${INGRESS_IP}/path"
fi

log "INFO" "Deployment completed successfully!"


cat > cleanup-ingress.sh << EOL



ENVIRONMENT="$ENVIRONMENT"
NAMESPACE="$NAMESPACE"
RELEASE_NAME="$RELEASE_NAME"


while [[ \$
    case \$1 in
        -e|--environment)
            ENVIRONMENT="\$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="\$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="\$2"
            shift 2
            ;;
        *)
            echo "Unknown option: \$1"
            exit 1
            ;;
    esac
done

echo "Cleaning up ingress resources..."


helm uninstall \${RELEASE_NAME} -n \${NAMESPACE}


read -p "Do you want to delete the namespace \${NAMESPACE}? (y/n) " -n 1 -r
echo
if [[ \$REPLY =~ ^[Yy]\$ ]]; then
    kubectl delete namespace \${NAMESPACE}
fi

echo "Cleanup completed successfully!"
EOL

chmod +x cleanup-ingress.sh