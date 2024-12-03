#!/bin/bash

CHART_NAME="vsaas-userportal"
RELEASE_NAME="vsaas-userportal"
NAMESPACE="vsaas-dev"
CHART_PATH="./vsaas-userportal"
VALUES_FILE="values.yaml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_section() {
    local message=$1
    echo -e "\n${BLUE}=== $message ===${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local prerequisites=("kubectl" "helm")
    local missing_prereqs=0
    
    for prereq in "${prerequisites[@]}"; do
        if ! command_exists "$prereq"; then
            print_message "$RED" "Error: $prereq is not installed"
            missing_prereqs=1
        else
            print_message "$GREEN" "✓ $prereq is installed"
        fi
    done
    
    if [ $missing_prereqs -eq 1 ]; then
        exit 1
    fi
}

create_namespace_if_not_exists() {
    print_section "Checking Namespace"
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_message "$YELLOW" "Namespace $NAMESPACE does not exist. Creating..."
        kubectl create namespace "$NAMESPACE"
        print_message "$GREEN" "✓ Namespace $NAMESPACE created successfully"
    else
        print_message "$GREEN" "✓ Namespace $NAMESPACE already exists"
    fi
}

validate_chart() {
    print_section "Validating Helm Chart"
    if ! helm lint "$CHART_PATH"; then
        print_message "$RED" "Error: Helm chart validation failed"
        exit 1
    fi
    print_message "$GREEN" "✓ Helm chart validation successful"
}

deploy_chart() {
    local action=$1
    local cmd="helm $action $RELEASE_NAME $CHART_PATH -n $NAMESPACE"
    
    if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
        cmd="$cmd -f $VALUES_FILE"
    fi
    
    if eval "$cmd"; then
        print_message "$GREEN" "✓ Chart $action successful"
    else
        print_message "$RED" "Error: Chart $action failed"
        exit 1
    fi
}

check_deployment_status() {
    print_section "Checking Deployment Status"
    kubectl rollout status deployment/$RELEASE_NAME -n $NAMESPACE
}

install() {
    print_section "Installing Chart"
    check_prerequisites
    create_namespace_if_not_exists
    validate_chart
    
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        print_message "$YELLOW" "Release already exists. Use upgrade command instead."
        exit 1
    fi
    
    deploy_chart "install"
    check_deployment_status
}

upgrade() {
    print_section "Upgrading Chart"
    check_prerequisites
    create_namespace_if_not_exists
    validate_chart
    
    if ! helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        print_message "$YELLOW" "Release does not exist. Use install command instead."
        exit 1
    fi
    
    deploy_chart "upgrade"
    check_deployment_status
}

check_resources() {
    if ! helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        print_message "$YELLOW" "No Helm release found for $RELEASE_NAME"
        return 1
    fi
    return 0
}

cleanup() {
    print_section "Cleanup Process"
    
    if ! check_resources; then
        print_message "$YELLOW" "Nothing to clean up"
        return 0
    fi
    
    read -p "Are you sure you want to cleanup the deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "$YELLOW" "Cleanup cancelled"
        return 1
    fi
    
    print_message "$BLUE" "Uninstalling Helm release..."
    if ! helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"; then
        print_message "$RED" "Failed to uninstall Helm release"
        return 1
    fi
    
    print_message "$BLUE" "Cleaning up additional resources..."
    
    kubectl delete configmap -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found
    
    kubectl delete pvc -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found
    
    kubectl delete secret -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found
    
    print_message "$GREEN" "✓ Cleanup completed successfully"
}

show_status() {
    print_section "Deployment Status"
    if ! helm status "$RELEASE_NAME" -n "$NAMESPACE"; then
        print_message "$YELLOW" "Release $RELEASE_NAME not found"
        return 1
    fi
    
    print_section "Kubernetes Resources"
    kubectl get all -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME"
}

usage() {
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  install     Install the Helm chart"
    echo "  upgrade     Upgrade the existing installation"
    echo "  cleanup     Remove the installation and cleanup resources"
    echo "  status      Show current deployment status"
    echo "  validate    Validate the Helm chart"
    echo
    echo "Example:"
    echo "  $0 install    # Install the chart"
    echo "  $0 cleanup    # Cleanup all resources"
}

case "$1" in
    install)
        install
        ;;
    upgrade)
        upgrade
        ;;
    cleanup)
        cleanup
        ;;
    status)
        show_status
        ;;
    validate)
        validate_chart
        ;;
    *)
        usage
        exit 1
        ;;
esac