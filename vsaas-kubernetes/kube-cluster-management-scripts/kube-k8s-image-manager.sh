#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

show_help() {
    echo -e "${GREEN}Kubernetes Image Management Script${NC}"
    echo -e "\nUsage:"
    echo "  ./k8s-image-manager.sh [command] [options]"
    echo -e "\nCommands:"
    echo "  list                     List all images in all namespaces"
    echo "  list-namespace [ns]      List images in specific namespace"
    echo "  list-inactive           List inactive/unused images"
    echo "  delete [image] [ns]      Delete specific image from namespace"
    echo "  cleanup                  Remove unused images"
    echo "  show-large              Show images larger than 1GB"
    echo -e "\nOptions:"
    echo "  -h, --help              Show this help message"
}

list_all_images() {
    echo -e "${GREEN}Listing all container images across all namespaces...${NC}"
    kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | \
    tr -s '[[:space:]]' '\n' | \
    sort | \
    uniq
}

list_namespace_images() {
    local namespace=$1
    if [ -z "$namespace" ]; then
        echo -e "${RED}Error: Namespace not specified${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Listing container images in namespace: ${YELLOW}$namespace${NC}"
    kubectl get pods -n "$namespace" -o jsonpath="{.items[*].spec.containers[*].image}" | \
    tr -s '[[:space:]]' '\n' | \
    sort | \
    uniq
}

list_inactive_images() {
    echo -e "${GREEN}Analyzing for inactive images...${NC}"
    
    echo -e "${YELLOW}Getting all images from nodes...${NC}"
    declare -A node_images
    while IFS= read -r node; do
        echo "Checking node: $node"
        kubectl debug node/$node -it --image=ubuntu -- crictl images -o json | \
        jq -r '.images[].repoTags[]' | while read -r image; do
            node_images["$image"]=1
        done
    done < <(kubectl get nodes -o name | cut -d'/' -f2)

    echo -e "${YELLOW}Getting actively used images...${NC}"
    declare -A active_images
    kubectl get pods --all-namespaces -o json | \
    jq -r '.items[].spec.containers[].image' | while read -r image; do
        active_images["$image"]=1
    done

    echo -e "${GREEN}Inactive images:${NC}"
    for image in "${!node_images[@]}"; do
        if [[ -z "${active_images[$image]}" ]]; then
            size=$(kubectl debug node/$(kubectl get nodes -o name | cut -d'/' -f2 | head -n1) -it --image=ubuntu -- \
                  crictl images --digests | grep "$image" | awk '{print $7}')
            echo -e "${YELLOW}$image${NC} (Size: $size)"
        fi
    done
}

delete_image() {
    local image=$1
    local namespace=$2

    if [ -z "$image" ]; then
        echo -e "${RED}Error: Image not specified${NC}"
        return 1
    fi

    if [ -z "$namespace" ]; then
        namespace="default"
    fi

    echo -e "${YELLOW}Warning: This will delete pods using image: $image in namespace: $namespace${NC}"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Deleting pods with image: $image${NC}"
        kubectl get pods -n "$namespace" -o json | \
        jq ".items[] | select(.spec.containers[].image==\"$image\") | .metadata.name" | \
        xargs -I {} kubectl delete pod {} -n "$namespace"
    fi
}

cleanup_images() {
    echo -e "${GREEN}Cleaning up unused images...${NC}"
    for node in $(kubectl get nodes -o name); do
        echo -e "${YELLOW}Cleaning up node: $node${NC}"
        kubectl debug "$node" -it --image=ubuntu -- crictl rmi --prune
    done
}

show_large_images() {
    echo -e "${GREEN}Showing images larger than 1GB...${NC}"
    kubectl get pods --all-namespaces -o json | \
    jq -r '.items[].spec.containers[].image' | \
    sort | uniq | \
    while read -r image; do
        size=$(docker image inspect "$image" 2>/dev/null | jq '.[].Size')
        if [ ! -z "$size" ] && [ "$size" -gt 1000000000 ]; then
            echo -e "${YELLOW}$image: $(($size/1000000))MB${NC}"
        fi
    done
}

case "$1" in
    list)
        list_all_images
        ;;
    list-namespace)
        list_namespace_images "$2"
        ;;
    list-inactive)
        list_inactive_images
        ;;
    delete)
        delete_image "$2" "$3"
        ;;
    cleanup)
        cleanup_images
        ;;
    show-large)
        show_large_images
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo -e "${RED}Error: Invalid command${NC}"
        show_help
        exit 1
        ;;
esac