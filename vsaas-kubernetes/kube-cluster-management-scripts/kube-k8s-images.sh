#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}Kubernetes Container Images Report${NC}"
echo "================================="

namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for namespace in $namespaces; do
    echo -e "\n${GREEN}Namespace: $namespace${NC}"
    echo "----------------"
    
    pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        echo -e "\nPod: $pod"
        
        init_containers=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.initContainers[*].image}' 2>/dev/null)
        if [ ! -z "$init_containers" ]; then
            echo "Init Containers:"
            for image in $init_containers; do
                echo "  - $image"
            done
        fi
        
        containers=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].image}')
        if [ ! -z "$containers" ]; then
            echo "Containers:"
            for image in $containers; do
                echo "  - $image"
            done
        fi
    done
done

echo -e "\n${BLUE}Summary of Unique Images:${NC}"
echo "======================="
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" |\
tr -s '[[:space:]]' '\n' |\
sort |\
uniq

