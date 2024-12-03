#!/bin/bash

echo "Listing all container images in the cluster..."
echo "============================================="

kubectl get pods --all-namespaces -o=custom-columns=\
"NAMESPACE:.metadata.namespace,"\
"POD:.metadata.name,"\
"CONTAINER:.spec.containers[*].name,"\
"IMAGE:.spec.containers[*].image"

echo -e "\nUnique images:"
echo "=============="
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" |\
tr -s '[[:space:]]' '\n' |\
sort |\
uniq

