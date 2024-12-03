ENVIRONMENT="dev"
NAMESPACE="ingress-nginx"
RELEASE_NAME="nginx-controller"
CHART_PATH="./vsaas-nginx-controller"
MONITORING_NAMESPACE="monitoring"
INSTALL_MONITORING="false"
ACTION="install"  

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 

log() {
    local level=$1
    shift
    local message=$@
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${level}] ${timestamp} - ${message}"
}

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -e, --environment     Environment (dev|staging|prod) [default: dev]"
    echo "  -n, --namespace       Namespace for Nginx controller [default: ingress-nginx]"
    echo "  -r, --release         Release name [default: nginx-controller]"
    echo "  -m, --monitoring      Install monitoring stack (true|false) [default: false]"
    echo "  -a, --action          Action to perform (install|cleanup) [default: install]"
    echo "  -h, --help           Show this help message"
}


install_prometheus_operator() {
    log "INFO" "Installing Prometheus Operator CRDs..."
    
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    
    kubectl create namespace ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace ${MONITORING_NAMESPACE} \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --wait \
        --timeout 5m
}


cleanup() {
    log "INFO" "Starting cleanup process..."

    
    if helm status $RELEASE_NAME -n $NAMESPACE >/dev/null 2>&1; then
        log "INFO" "Uninstalling Nginx Ingress Controller..."
        helm uninstall $RELEASE_NAME -n $NAMESPACE
        
        sleep 10
    else
        log "INFO" "Nginx Ingress Controller release not found in namespace $NAMESPACE"
    fi

    
    if helm list -n $MONITORING_NAMESPACE 2>/dev/null | grep -q "prometheus"; then
        log "INFO" "Found Prometheus Operator installation..."
        
        log "INFO" "Uninstalling Prometheus Operator..."
        helm uninstall prometheus -n $MONITORING_NAMESPACE
        
        sleep 20
    else
        log "INFO" "Prometheus Operator release not found in namespace $MONITORING_NAMESPACE"
    fi

    
    echo -e "\n${YELLOW}Do you want to delete the following namespaces?${NC}"
    echo "1. $NAMESPACE (Nginx Ingress Controller namespace)"
    if kubectl get namespace $MONITORING_NAMESPACE >/dev/null 2>&1; then
        echo "2. $MONITORING_NAMESPACE (Monitoring namespace)"
    fi
    
    read -p "Delete namespaces? (yes/no): " DELETE_NAMESPACES
    if [[ "$DELETE_NAMESPACES" =~ ^[Yy][Ee][Ss]$ ]]; then
        
        if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
            log "INFO" "Deleting namespace: $NAMESPACE"
            kubectl delete namespace $NAMESPACE --timeout=60s
            
            while kubectl get namespace $NAMESPACE >/dev/null 2>&1; do
                log "INFO" "Waiting for namespace $NAMESPACE to be deleted..."
                sleep 5
            done
        fi

        
        if kubectl get namespace $MONITORING_NAMESPACE >/dev/null 2>&1; then
            log "INFO" "Deleting namespace: $MONITORING_NAMESPACE"
            
            for resource in $(kubectl get -n $MONITORING_NAMESPACE prometheus,alertmanager,servicemonitor,podmonitor -o name 2>/dev/null); do
                kubectl patch -n $MONITORING_NAMESPACE $resource -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
            
            
            kubectl delete namespace $MONITORING_NAMESPACE --timeout=60s
            
            
            while kubectl get namespace $MONITORING_NAMESPACE >/dev/null 2>&1; do
                log "INFO" "Waiting for namespace $MONITORING_NAMESPACE to be deleted..."
                sleep 5
            done
        fi
    fi

    
    echo -e "\n${YELLOW}Do you want to delete Prometheus CRDs?${NC}"
    echo "Warning: This will affect other applications that might be using these CRDs"
    read -p "Delete Prometheus CRDs? (yes/no): " DELETE_CRDS
    if [[ "$DELETE_CRDS" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Deleting Prometheus CRDs..."
        PROMETHEUS_CRDS=(
            "prometheusrules.monitoring.coreos.com"
            "servicemonitors.monitoring.coreos.com"
            "podmonitors.monitoring.coreos.com"
            "alertmanagerconfigs.monitoring.coreos.com"
            "alertmanagers.monitoring.coreos.com"
            "probes.monitoring.coreos.com"
            "prometheuses.monitoring.coreos.com"
            "thanosrulers.monitoring.coreos.com"
        )
        
        for crd in "${PROMETHEUS_CRDS[@]}"; do
            if kubectl get crd $crd >/dev/null 2>&1; then
                log "INFO" "Deleting CRD: $crd"
                kubectl delete crd $crd --timeout=30s
            fi
        done
    fi

    log "INFO" "Cleanup completed successfully!"
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
        -m|--monitoring)
            INSTALL_MONITORING="$2"
            shift 2
            ;;
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done


if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    log "ERROR" "Invalid environment. Must be one of: dev, staging, prod"
    exit 1
fi


if [[ ! "$INSTALL_MONITORING" =~ ^(true|false)$ ]]; then
    log "ERROR" "Invalid monitoring option. Must be either 'true' or 'false'"
    exit 1
fi


if [[ ! "$ACTION" =~ ^(install|cleanup)$ ]]; then
    log "ERROR" "Invalid action. Must be either 'install' or 'cleanup'"
    exit 1
fi


if [ "$ACTION" = "cleanup" ]; then
    cleanup
    exit 0
fi


if [ "$INSTALL_MONITORING" = "true" ]; then
    if ! kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
        log "INFO" "Prometheus CRDs not found. Installing Prometheus Operator..."
        install_prometheus_operator
    else
        log "INFO" "Prometheus CRDs already exist, skipping operator installation"
    fi
fi


log "INFO" "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -


log "INFO" "Deploying Nginx Ingress Controller to ${ENVIRONMENT} environment"
helm upgrade --install $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    -f $CHART_PATH/values.yaml \
    -f $CHART_PATH/values-${ENVIRONMENT}.yaml \
    --set controller.metrics.enabled=$INSTALL_MONITORING \
    --set controller.metrics.serviceMonitor.enabled=$INSTALL_MONITORING \
    --set controller.metrics.prometheusRule.enabled=$INSTALL_MONITORING \
    --wait \
    --timeout 30s


log "INFO" "Waiting for controller deployment to be ready"
kubectl wait --namespace $NAMESPACE \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=$RELEASE_NAME \
    --timeout=30s || true


EXTERNAL_IP=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$EXTERNAL_IP" = "pending" ]; then
    EXTERNAL_IP=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
fi

echo -e "\n${GREEN}=== Nginx Ingress Controller Access Information ===${NC}"
echo -e "External IP/Hostname: $EXTERNAL_IP"
echo -e "To check the service status:"
echo -e "kubectl get svc -n $NAMESPACE $RELEASE_NAME-nginx-ingress"


if [ "$INSTALL_MONITORING" = "true" ]; then
    echo -e "\n${YELLOW}=== Monitoring Access Information ===${NC}"
    echo -e "Prometheus UI: kubectl port-forward -n ${MONITORING_NAMESPACE} svc/prometheus-operated 9090:9090"
    echo -e "Grafana UI: kubectl port-forward -n ${MONITORING_NAMESPACE} svc/prometheus-grafana 3000:80"
    echo -e "Default Grafana credentials:"
    echo -e "Username: admin"
    echo -e "Password: prom-operator"
fi

log "INFO" "Deployment completed successfully!"