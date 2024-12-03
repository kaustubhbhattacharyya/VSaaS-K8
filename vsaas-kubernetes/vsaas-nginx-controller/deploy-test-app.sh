#!/bin/bash
# deploy-test-app.sh

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to log messages
log() {
    local level=$1
    shift
    local message=$@
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${level}] ${timestamp} - ${message}"
}

# Deploy the test application
deploy_test_app() {
    # Create namespace
    log "INFO" "Creating test namespace..."
    kubectl apply -f test-app/namespace.yaml

    # Apply deployments
    log "INFO" "Deploying test application..."
    kubectl apply -f test-app/deployment.yaml
    kubectl apply -f test-app/service.yaml
    kubectl apply -f test-app/ingress.yaml
    kubectl apply -f test-app/configmap.yaml

    # Wait for deployment
    log "INFO" "Waiting for deployment to be ready..."
    kubectl -n test wait --for=condition=available --timeout=20s deployment/test-app

    # Display information
    echo -e "\n${GREEN}=== Test Application Deployment Information ===${NC}"
    echo -e "Namespace: test"
    echo -e "Service: test-app-service"
    echo -e "Port: 23050"
    echo -e "Access URL: http://test-app.example.com/app"
    
    # Get Ingress IP/Hostname
    INGRESS_IP=$(kubectl -n test get ingress test-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$INGRESS_IP" ]; then
        INGRESS_IP=$(kubectl -n test get ingress test-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    fi
    
    if [ ! -z "$INGRESS_IP" ]; then
        echo -e "Ingress IP/Hostname: $INGRESS_IP"
        echo -e "\nAdd the following to your /etc/hosts file:"
        echo -e "$INGRESS_IP test-app.example.com"
    fi

    # Test commands
    echo -e "\n${YELLOW}=== Test Commands ===${NC}"
    echo -e "Test service: kubectl -n test port-forward svc/test-app-service 23050:23050"
    echo -e "View pods: kubectl -n test get pods"
    echo -e "View logs: kubectl -n test logs -l app=test-app"
    echo -e "Curl test: curl -H 'Host: test-app.example.com' http://\$INGRESS_IP/app"
}

# Cleanup function
cleanup_test_app() {
    log "INFO" "Cleaning up test application..."
    
    # Delete resources
    kubectl delete -f test-app/ingress.yaml 2>/dev/null || true
    kubectl delete -f test-app/service.yaml 2>/dev/null || true
    kubectl delete -f test-app/deployment.yaml 2>/dev/null || true
    kubectl delete -f test-app/configmap.yaml 2>/dev/null || true
    
    # Ask about namespace deletion
    read -p "Delete test namespace? (yes/no): " DELETE_NS
    if [[ "$DELETE_NS" =~ ^[Yy][Ee][Ss]$ ]]; then
        kubectl delete -f test-app/namespace.yaml
    fi
    
    log "INFO" "Cleanup completed"
}

# Parse command line arguments
ACTION="deploy"
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute action
case $ACTION in
    deploy)
        deploy_test_app
        ;;
    cleanup)
        cleanup_test_app
        ;;
    *)
        log "ERROR" "Invalid action. Use 'deploy' or 'cleanup'"
        exit 1
        ;;
esac