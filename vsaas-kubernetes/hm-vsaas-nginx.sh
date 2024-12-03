
NAMESPACE="vsaas-dev"
VALUES_FILE="vsaas-nginx/values.yaml"
RELEASE_NAME="vsaas-nginx"


function show_help() {
    echo "Usage: $0 [command] [options]"
    echo "Commands:"
    echo "  install         Install the NGINX Ingress Controller"
    echo "  uninstall       Uninstall the NGINX Ingress Controller"
    echo "  help            Show this help message"
    echo "Options:"
    echo "  -n, --namespace <namespace>  Specify the Kubernetes namespace (default: $NAMESPACE)"
    echo "  -f, --values-file <file>     Specify the values.yaml file (default: $VALUES_FILE)"
    echo "  -r, --release-name <name>    Specify the Helm release name (default: $RELEASE_NAME)"
}


function install_ingress() {
    helm install "$RELEASE_NAME" ingress-nginx/ingress-nginx --namespace "$NAMESPACE" -f "$VALUES_FILE"
}


function uninstall_ingress() {
    helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
}


while [[ $
    key="$1"
    case $key in
        install)
            install_ingress
            exit 0
            ;;
        uninstall)
            uninstall_ingress
            exit 0
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift
            shift
            ;;
        -f|--values-file)
            VALUES_FILE="$2"
            shift
            shift
            ;;
        -r|--release-name)
            RELEASE_NAME="$2"
            shift
            shift
            ;;
        help)
            show_help
            exit 0
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done


show_help