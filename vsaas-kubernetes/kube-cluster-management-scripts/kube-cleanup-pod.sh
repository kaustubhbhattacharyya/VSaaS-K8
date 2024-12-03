#!/bin/bash

# kube-cleanup-pod
# Description: A comprehensive script for cleaning up Kubernetes pods and related resources
# Usage: ./kube-cleanup-pod [-p pod_name] [-n namespace] [-f] [-a] [-i] [-l label] [-h]

set -e 

FORCE=false
ALL_PODS=false
INCLUDE_IMAGES=false
DRY_RUN=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --pod POD_NAME      Specify pod name to cleanup"
    echo "  -n, --namespace NS      Specify namespace (default: default)"
    echo "  -f, --force            Force deletion without confirmation"
    echo "  -a, --all              Delete all pods in specified namespace"
    echo "  -i, --images           Also cleanup unused images"
    echo "  -l, --label LABEL      Select pods by label (e.g., 'app=myapp')"
    echo "  -d, --dry-run          Show what would be deleted without actually deleting"
    echo "  -h, --help             Display this help message"
    exit 1
}

# Function to log messages
log() {
    local level=$1
    local msg=$2
    local color=$NC
    
    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
    esac
    
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg${NC}"
}

# Function to confirm action
confirm() {
    if [ "$FORCE" = false ]; then
        read -p "Are you sure you want to proceed? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Operation cancelled by user"
            exit 1
        fi
    fi
}

# Function to cleanup images
cleanup_images() {
    local namespace=$1
    local pod_name=$2
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would cleanup images for pod $pod_name in namespace $namespace"
        return
    fi
    
    log "INFO" "Retrieving container images for pod $pod_name..."
    local images=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)
    
    if [ -n "$images" ]; then
        log "INFO" "Cleaning up container images..."
        for image in $images; do
            crictl rmi $image || log "WARN" "Failed to remove image: $image"
        done
        
        log "INFO" "Cleaning up unused images..."
        crictl rmi --prune || log "WARN" "Failed to prune unused images"
    fi
}

# Function to delete pod
delete_pod() {
    local namespace=$1
    local pod_name=$2
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete pod $pod_name in namespace $namespace"
        return
    fi
    
    log "INFO" "Deleting pod $pod_name in namespace $namespace..."
    kubectl delete pod $pod_name -n $namespace --grace-period=0 --force || {
        log "ERROR" "Failed to delete pod $pod_name"
        return 1
    }
    
    if [ "$INCLUDE_IMAGES" = true ]; then
        cleanup_images "$namespace" "$pod_name"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pod)
            POD_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -a|--all)
            ALL_PODS=true
            shift
            ;;
        -i|--images)
            INCLUDE_IMAGES=true
            shift
            ;;
        -l|--label)
            LABEL="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate inputs
NAMESPACE=${NAMESPACE:-default}

if [ "$ALL_PODS" = false ] && [ -z "$POD_NAME" ] && [ -z "$LABEL" ]; then
    log "ERROR" "Either pod name (-p), label (-l), or --all (-a) must be specified"
    usage
fi

# Main execution
log "INFO" "Starting cleanup process..."
log "INFO" "Namespace: $NAMESPACE"

if [ "$DRY_RUN" = true ]; then
    log "INFO" "Running in DRY RUN mode - no actual deletions will occur"
fi

# Get list of pods to delete
if [ "$ALL_PODS" = true ]; then
    PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
elif [ -n "$LABEL" ]; then
    PODS=$(kubectl get pods -n $NAMESPACE -l $LABEL -o jsonpath='{.items[*].metadata.name}')
else
    PODS=$POD_NAME
fi

# Confirm action
if [ -n "$PODS" ]; then
    log "INFO" "The following pods will be deleted:"
    for pod in $PODS; do
        echo "  - $pod"
    done
    confirm
    
    # Delete pods
    for pod in $PODS; do
        delete_pod "$NAMESPACE" "$pod"
    done
    
    log "INFO" "Cleanup completed successfully"
else
    log "WARN" "No pods found matching the specified criteria"
fi

# Final cleanup
if [ "$INCLUDE_IMAGES" = true ] && [ "$DRY_RUN" = false ]; then
    log "INFO" "Performing final image cleanup..."
    crictl rmi --prune || log "WARN" "Failed to perform final image pruning"
fi