

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="ingress-nginx"
RELEASE_NAME="nginx-ingress"
CHART_VERSION="4.7.1"
VALUES_FILE="values.yaml"
PUBLIC_IP=""

NGINX_DEPLOYMENT=""
NGINX_SERVICE=""
METRICS_SERVICE=""
DASHBOARD_SERVICE=""

UNINSTALL=false
DRY_RUN=false
BACKUP=false
FORCE=false

error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}$1${NC}"; }
warning() { echo -e "${YELLOW}Warning: $1${NC}"; }

usage() {
    cat << EOF
Usage: $0 [options]

Required:
    -i, --ip            Public IP to use for LoadBalancer

Options:
    -n, --namespace     Namespace for installation (default: ingress-nginx)
    -r, --release       Release name (default: nginx-ingress)
    -v, --version       Chart version (default: 4.7.1)
    --uninstall        Uninstall the ingress controller
    --dry-run         Perform a dry run
    --backup          Create backup before changes
    -f, --force       Force operations without confirmation
    -h, --help        Show this help message

Examples:
    $0 -i 192.168.1.100                     
    $0 -i 192.168.1.100 -n custom-ns        
    $0 --uninstall                          
    $0 --dry-run -i 192.168.1.100           
EOF
}

set_resource_names() {
    NGINX_DEPLOYMENT="${RELEASE_NAME}-ingress-nginx-controller"
    NGINX_SERVICE="${RELEASE_NAME}-ingress-nginx-controller"
    METRICS_SERVICE="${RELEASE_NAME}-metrics"
    DASHBOARD_SERVICE="${RELEASE_NAME}-dashboard"
}

check_requirements() {
    command -v kubectl >/dev/null 2>&1 || error "kubectl is required but not installed"
    command -v helm >/dev/null 2>&1 || {
        warning "Helm is not installed. Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    }
    kubectl cluster-info >/dev/null 2>&1 || error "kubectl cannot access the cluster"
    
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Installing jq..."
        apt-get update && apt-get install -y jq || true
    fi

    set_resource_names
}

validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "Invalid IP address format: $ip"
    fi
}

parse_args() {
    while [[ $
        case $1 in
            -i|--ip)
                PUBLIC_IP="$2"
                validate_ip "$PUBLIC_IP"
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
            -v|--version)
                CHART_VERSION="$2"
                shift 2
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --backup)
                BACKUP=true
                shift
                ;;
            --auth)
                ENABLE_AUTH=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    if [ "$UNINSTALL" = false ] && [ -z "$PUBLIC_IP" ]; then
        error "Public IP is required for installation. Use -i or --ip option."
    fi
}


create_values_file() {
    cat > $VALUES_FILE <<EOF
controller:
  name: controller
  image:
    repository: registry.k8s.io/ingress-nginx/controller
    tag: "v1.8.1"
    pullPolicy: IfNotPresent
  
  replicaCount: 1

  
  service:
    enabled: true
    type: LoadBalancer
    loadBalancerIP: "${PUBLIC_IP}"
    annotations:
      metallb.universe.tf/loadBalancerIPs: "${PUBLIC_IP}"
      metallb.universe.tf/address-pool: "first-pool"
    externalTrafficPolicy: Local
    ports:
      http: 80
      https: 443

  
  podLabels:
    app: ingress-nginx
  
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10254"

  
  metrics:
    port: 10254
    enabled: true
    service:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "10254"

  
  containerPorts:
    http: 80
    https: 443

  
  config:
    enable-real-ip: "true"
    proxy-body-size: "200m"
    proxy-connect-timeout: "600"
    proxy-read-timeout: "600"
    proxy-send-timeout: "600"
    enable-metrics: "true"
    
  
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

  
  extraArgs:
    enable-ssl-passthrough: false

namespaceOverride: "${NAMESPACE}"
EOF

    if [ $? -ne 0 ]; then
        error "Failed to create values file"
        return 1
    fi

    success "Values file created successfully"
    return 0
}




    



    


    






    

























configure_dashboard() {
    echo "Configuring dashboard..."

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${METRICS_SERVICE}
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  ports:
    - name: metrics
      port: 10254
      targetPort: metrics
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ${RELEASE_NAME}
EOF

    sleep 5

    echo "Dashboard will be accessible at: http://${PUBLIC_IP}:10254/dashboard"
}

install_controller() {
    echo "Starting Nginx Ingress Controller installation..."

    echo "Cleaning up existing MetalLB installation..."
    kubectl delete namespace metallb-system --timeout=60s 2>/dev/null || true
    kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration 2>/dev/null || true
    
    echo "Waiting for MetalLB cleanup..."
    while kubectl get namespace metallb-system >/dev/null 2>&1; do
        echo "Waiting for metallb-system namespace to be deleted..."
        sleep 2
    done
    
    echo "Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

    echo "Waiting for MetalLB pods to be ready..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=300s || {
        error "MetalLB pods failed to become ready"
        return 1
    }

    echo "Waiting for MetalLB controller..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=component=controller \
        --timeout=300s || {
        error "MetalLB controller failed to become ready"
        return 1
    }

    echo "Configuring webhook..."
    cat <<EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: metallb-webhook-configuration
  labels:
    app: metallb
webhooks:
- name: ipaddresspoolvalidationwebhook.metallb.io
  failurePolicy: Ignore
  sideEffects: None
  admissionReviewVersions: ["v1"]
  timeoutSeconds: 30
  clientConfig:
    service:
      name: controller
      namespace: metallb-system
      path: "/validate-metallb-io-v1beta1-ipaddresspool"
  rules:
  - apiGroups: ["metallb.io"]
    apiVersions: ["v1beta1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["ipaddresspools"]
    scope: "Namespaced"
EOF

    echo "Waiting for webhook configuration to be applied..."
    sleep 10

    check_metallb_ready() {
        local retries=0
        local max_retries=10
        
        while [ $retries -lt $max_retries ]; do
            if kubectl get pods -n metallb-system -l component=controller -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
                return 0
            fi
            echo "Waiting for MetalLB controller to be ready... Attempt $((retries+1))/$max_retries"
            sleep 5
            ((retries++))
        done
        return 1
    }

    echo "Verifying MetalLB readiness..."
    if ! check_metallb_ready; then
        error "MetalLB failed to become ready"
        return 1
    fi

    echo "Configuring MetalLB IP pool..."
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${PUBLIC_IP}/32
  autoAssign: true
EOF

    if ! kubectl get ipaddresspool -n metallb-system first-pool >/dev/null 2>&1; then
        error "Failed to create IPAddressPool"
        kubectl get events -n metallb-system
        return 1
    fi

    echo "Waiting for IPAddressPool to be processed..."
    sleep 10

    echo "Configuring MetalLB L2 Advertisement..."
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF

    if ! kubectl get l2advertisement -n metallb-system l2-advert >/dev/null 2>&1; then
        error "Failed to create L2Advertisement"
        kubectl get events -n metallb-system
        return 1
    fi

    echo "Waiting for L2Advertisement to be processed..."
    sleep 10

    echo "Verifying MetalLB configuration..."
    kubectl get pods -n metallb-system
    kubectl get ipaddresspool,l2advertisement -n metallb-system

    kubectl create namespace "$NAMESPACE" 2>/dev/null || true

    create_values_file

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    if [ "$DRY_RUN" = true ]; then
        helm upgrade --install "$RELEASE_NAME" ingress-nginx/ingress-nginx \
            --namespace "$NAMESPACE" \
            --version "$CHART_VERSION" \
            --values "$VALUES_FILE" \
            --debug \
            --dry-run
    else
        echo "Installing Nginx Ingress Controller..."
        helm upgrade --install "$RELEASE_NAME" ingress-nginx/ingress-nginx \
            --namespace "$NAMESPACE" \
            --version "$CHART_VERSION" \
            --values "$VALUES_FILE" \
            --debug \
            --timeout 15m \
            --wait \
            --atomic

        verify_loadbalancer_ip
    fi
}

verify_loadbalancer_ip() {
    echo "Verifying LoadBalancer IP assignment..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        EXTERNAL_IP=$(kubectl get svc "$RELEASE_NAME-ingress-nginx-controller" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ "$EXTERNAL_IP" = "$PUBLIC_IP" ]; then
            success "Service successfully got IP: $EXTERNAL_IP"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "Waiting for LoadBalancer IP... Attempt $attempt/$max_attempts"
        sleep 10
    done

    error "Failed to assign LoadBalancer IP after $max_attempts attempts"
    return 1
}

uninstall_controller() {
    echo "Uninstalling Nginx Ingress Controller..."

    if [ "$BACKUP" = true ]; then
        create_backup
    fi

    if [ "$FORCE" = false ]; then
        read -p "Are you sure you want to uninstall? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true

    kubectl delete namespace $NAMESPACE 2>/dev/null || true

    kubectl delete ipaddresspool -n metallb-system first-pool 2>/dev/null || true
    kubectl delete l2advertisement -n metallb-system l2-advert 2>/dev/null || true

    success "Uninstallation completed"
}

verify_metallb_status() {
    echo "Verifying MetalLB status..."
    
    echo "MetalLB Pods:"
    kubectl get pods -n metallb-system
    
    echo -e "\nMetalLB Speaker Status:"
    kubectl logs -n metallb-system -l component=speaker --tail=20
    
    echo -e "\nMetalLB Configuration:"
    kubectl get ipaddresspools,l2advertisements -n metallb-system
}

create_backup() {
    local backup_dir="nginx-ingress-backup-$(date +%Y%m%d-%H%M%S)"
    echo "Creating backup in $backup_dir..."
    mkdir -p $backup_dir

    helm get values $RELEASE_NAME -n $NAMESPACE > "$backup_dir/values.yaml" 2>/dev/null || true

    kubectl get all -n $NAMESPACE -o yaml > "$backup_dir/resources.yaml" 2>/dev/null || true
    kubectl get configmap -n $NAMESPACE -o yaml > "$backup_dir/configmaps.yaml" 2>/dev/null || true
    kubectl get secret -n $NAMESPACE -o yaml > "$backup_dir/secrets.yaml" 2>/dev/null || true

    success "Backup completed in $backup_dir"
}

get_resource_names() {
    NGINX_DEPLOYMENT="${RELEASE_NAME}-ingress-nginx-controller"
    NGINX_SERVICE="${RELEASE_NAME}-ingress-nginx-controller"
    METRICS_SERVICE="${RELEASE_NAME}-metrics"
    DASHBOARD_SERVICE="${RELEASE_NAME}-dashboard"
}

check_deployment() {
    local ns=$1
    local deploy=$2
    
    echo "Checking deployment: $deploy in namespace: $ns"
    
    
    if ! kubectl get deployment "$deploy" -n "$ns" >/dev/null 2>&1; then
        return 1
    fi

    
    local ready=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}')
    if [ "$ready" != "1" ]; then
        return 1
    fi

    return 0
}




setup_metallb() {
    echo "Setting up MetalLB..."
    local VERSION="v0.13.7"
    local TIMEOUT=300
    
    
    cleanup_metallb || warning "MetalLB cleanup failed, continuing with setup..."
    
    
    echo "Installing MetalLB version $VERSION..."
    (
        
        kubectl create namespace metallb-system || return 1
        
        
        kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/$VERSION/config/manifests/metallb-native.yaml" || return 1
        
        
        echo "Waiting for MetalLB pods to be ready..."
        kubectl wait --namespace metallb-system \
            --for=condition=ready pod \
            --selector=app=metallb \
            --timeout=120s || return 1
            
        
        configure_webhook || return 1
        
        return 0
    ) & 

    
    local pid=$!
    local counter=0
    while kill -0 $pid 2>/dev/null; do
        if [ $counter -ge $TIMEOUT ]; then
            kill $pid 2>/dev/null
            error "MetalLB installation timed out after ${TIMEOUT} seconds"
        fi
        sleep 1
        ((counter++))
    done

    wait $pid || error "MetalLB installation failed"
    
    
    if ! configure_metallb_addresspool; then
        error "Failed to configure MetalLB address pool"
    fi
    
    
    echo "Verifying MetalLB installation..."
    (
        verify_metallb
    ) & 
    
    
    pid=$!
    counter=0
    while kill -0 $pid 2>/dev/null; do
        if [ $counter -ge 60 ]; then
            kill $pid 2>/dev/null
            error "MetalLB verification timed out after 60 seconds"
        fi
        sleep 1
        ((counter++))
    done

    wait $pid || error "MetalLB verification failed"
    
    success "MetalLB setup completed successfully"
    return 0
}


cleanup_metallb() {
    echo "Cleaning up existing MetalLB installation..."
    
    
    kubectl delete namespace metallb-system --timeout=60s 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration 2>/dev/null || true
    kubectl delete crd ipaddresspools.metallb.io l2advertisements.metallb.io 2>/dev/null || true
    
    
    while kubectl get namespace metallb-system >/dev/null 2>&1; do
        echo "Waiting for metallb-system namespace to be deleted..."
        sleep 5
    done
}


install_metallb() {
    local version=$1
    echo "Installing MetalLB version $version..."
    
    
    kubectl create namespace metallb-system
    
    
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/$version/config/manifests/metallb-native.yaml
    
    
    echo "Waiting for MetalLB pods to be ready..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=120s || {
            error "MetalLB pods failed to become ready"
            return 1
        }
    
    
    configure_webhook
}


configure_webhook() {
    echo "Configuring MetalLB webhook..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: metallb-webhook-configuration
  labels:
    app: metallb
webhooks:
- name: ipaddresspoolvalidationwebhook.metallb.io
  failurePolicy: Ignore
  sideEffects: None
  admissionReviewVersions: ["v1"]
  timeoutSeconds: 30
  clientConfig:
    service:
      name: webhook-service
      namespace: metallb-system
      path: "/validate-metallb-io-v1beta1-ipaddresspool"
  rules:
  - apiGroups: ["metallb.io"]
    apiVersions: ["v1beta1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["ipaddresspools"]
    scope: "Namespaced"
EOF

    
    sleep 10
}


configure_metallb_addresspool() {
    echo "Configuring MetalLB address pool..."
    
    
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${PUBLIC_IP}/32
  autoAssign: true
EOF

    
    sleep 5

    
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
}


verify_metallb() {
    echo "Verifying MetalLB installation..."
    local namespace="metallb-system"
    local success=true

    
    echo "Checking MetalLB pods..."
    if ! kubectl get pods -n $namespace -l app=metallb | grep -q "Running"; then
        warning "MetalLB pods are not running"
        kubectl get pods -n $namespace -l app=metallb
        success=false
    fi

    
    echo "Checking MetalLB controller..."
    if ! kubectl get pods -n $namespace -l component=controller | grep -q "Running"; then
        warning "MetalLB controller is not running"
        kubectl describe pods -n $namespace -l component=controller
        success=false
    fi

    
    echo "Checking MetalLB speaker..."
    if ! kubectl get pods -n $namespace -l component=speaker | grep -q "Running"; then
        warning "MetalLB speaker is not running"
        kubectl describe pods -n $namespace -l component=speaker
        success=false
    fi

    
    echo "Checking IP address pool..."
    if ! kubectl get ipaddresspools -n $namespace first-pool >/dev/null 2>&1; then
        warning "IP address pool not found"
        success=false
    fi

    
    echo "Checking L2 advertisement..."
    if ! kubectl get l2advertisements -n $namespace l2-advert >/dev/null 2>&1; then
        warning "L2 advertisement not found"
        success=false
    fi

    
    echo -e "\nMetalLB Status:"
    kubectl get all -n $namespace

    
    echo -e "\nIP Address Pools:"
    kubectl get ipaddresspools -n $namespace -o wide

    
    echo -e "\nL2 Advertisements:"
    kubectl get l2advertisements -n $namespace -o wide

    
    echo -e "\nRecent MetalLB Events:"
    kubectl get events -n $namespace --sort-by='.lastTimestamp' | tail -n 5

    if [ "$success" = true ]; then
        success "MetalLB verification completed successfully"
    else
        error "MetalLB verification failed"
    fi
}


monitor_metallb() {
    local namespace="metallb-system"
    
    echo "Monitoring MetalLB..."
    
    
    echo "Pod Status:"
    kubectl get pods -n $namespace -o wide
    
    
    echo -e "\nController Logs:"
    kubectl logs -n $namespace -l component=controller --tail=20
    
    
    echo -e "\nSpeaker Logs:"
    kubectl logs -n $namespace -l component=speaker --tail=20
    
    
    echo -e "\nIP Assignments:"
    kubectl get services --all-namespaces -o json | \
        jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name): \(.status.loadBalancer.ingress[0].ip)"'
}


test_metallb() {
    local namespace="metallb-system"
    
    echo "Testing MetalLB configuration..."
    
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: metallb-test
  namespace: default
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: metallb-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metallb-test
  namespace: default
spec:
  selector:
    matchLabels:
      app: metallb-test
  template:
    metadata:
      labels:
        app: metallb-test
    spec:
      containers:
      - name: nginx
        image: nginx:stable
        ports:
        - containerPort: 80
EOF

    
    echo "Waiting for IP assignment..."
    sleep 10
    
    
    kubectl get svc metallb-test
    
    
    kubectl delete service metallb-test
    kubectl delete deployment metallb-test
}


troubleshoot_metallb() {
    local namespace="metallb-system"
    
    echo "Troubleshooting MetalLB..."
    
    
    echo "1. Checking MetalLB components..."
    kubectl get pods -n $namespace
    
    
    echo -e "\n2. Checking speaker status..."
    kubectl logs -n $namespace -l component=speaker --tail=50
    
    
    echo -e "\n3. Checking configuration..."
    kubectl get ipaddresspools,l2advertisements -n $namespace -o yaml
    
    
    echo -e "\n4. Checking events..."
    kubectl get events -n $namespace --sort-by='.lastTimestamp'
    
    
    echo -e "\n5. Checking network connectivity..."
    local speaker_pod=$(kubectl get pod -n $namespace -l component=speaker -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n $namespace $speaker_pod -- ip addr
}




setup_dashboard() {
    echo "Setting up Nginx Ingress Dashboard..."
    
    
    configure_dashboard_components
    
    
    create_dashboard_services
    
    
    configure_dashboard_access
    
    
    verify_dashboard_setup
}


configure_dashboard_components() {
    echo "Configuring dashboard components..."
    
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${RELEASE_NAME}-ingress-nginx-controller
  namespace: ${NAMESPACE}
data:
  enable-prometheus-metrics: "true"
  enable-metrics: "true"
  enable-health-status: "true"
  enable-status-port: "true"
  metrics-per-host: "true"
  status-port: "10254"
  prometheus-metrics-port: "10254"
  http-snippets: |
    server {
      listen 10254;
      location /dashboard {
        root /usr/share/nginx/html;
        try_files \$uri \$uri/index.html /dashboard.html;
      }
      location /metrics {
        stub_status on;
        access_log off;
      }
      location /health {
        access_log off;
        return 200 "healthy\n";
      }
    }
EOF

    
    sleep 5
}


create_dashboard_services() {
    echo "Creating dashboard services..."
    
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${RELEASE_NAME}-dashboard
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ingress-nginx-dashboard
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: ClusterIP
  ports:
    - name: dashboard
      port: 10254
      targetPort: 10254
      protocol: TCP
    - name: metrics
      port: 9113
      targetPort: 10254
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ${RELEASE_NAME}
---
apiVersion: v1
kind: Service
metadata:
  name: ${RELEASE_NAME}-metrics
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ingress-nginx-metrics
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: LoadBalancer
  loadBalancerIP: "${PUBLIC_IP}"
  ports:
    - name: metrics
      port: 10254
      targetPort: 10254
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ${RELEASE_NAME}
EOF
}


configure_dashboard_access() {
    echo "Configuring dashboard access..."
    
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${RELEASE_NAME}-dashboard
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/rewrite-target: /dashboard
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Accept-Encoding "";
      sub_filter '</head>' '<link rel="stylesheet" type="text/css" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css"></head>';
      sub_filter_once on;
spec:
  ingressClassName: nginx
  rules:
  - host: "${PUBLIC_IP}.nip.io"
    http:
      paths:
      - path: /dashboard
        pathType: Prefix
        backend:
          service:
            name: ${RELEASE_NAME}-dashboard
            port:
              number: 10254
EOF
}


verify_dashboard_setup() {
    echo "Verifying dashboard setup..."
    local success=true
    local endpoints=(
        "/dashboard"
        "/metrics"
        "/health"
    )
    
    
    echo "Checking services..."
    for svc in "${RELEASE_NAME}-dashboard" "${RELEASE_NAME}-metrics"; do
        if ! kubectl get svc -n ${NAMESPACE} $svc >/dev/null 2>&1; then
            warning "Service $svc not found"
            success=false
        fi
    done
    
    
    echo "Checking ingress..."
    if ! kubectl get ingress -n ${NAMESPACE} ${RELEASE_NAME}-dashboard >/dev/null 2>&1; then
        warning "Dashboard ingress not found"
        success=false
    fi
    
    
    echo "Testing endpoints..."
    local pod_name=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=${RELEASE_NAME} -o jsonpath='{.items[0].metadata.name}')
    kubectl port-forward -n ${NAMESPACE} $pod_name 10254:10254 &
    local pf_pid=$!
    sleep 5
    
    for endpoint in "${endpoints[@]}"; do
        echo "Testing http://localhost:10254${endpoint}"
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:10254${endpoint}"; then
            success "Endpoint ${endpoint} is accessible"
        else
            warning "Failed to access endpoint ${endpoint}"
            success=false
        fi
    done
    
    
    kill $pf_pid 2>/dev/null
    
    
    show_dashboard_access
    
    if [ "$success" = false ]; then
        error "Dashboard verification failed"
    fi
}


show_dashboard_access() {
    echo -e "\nNginx Dashboard Access Methods:"
    echo "1. Using Domain (nip.io):"
    echo "   http://${PUBLIC_IP}.nip.io/dashboard"
    
    echo -e "\n2. Using Direct IP:"
    echo "   http://${PUBLIC_IP}:10254/dashboard"
    
    echo -e "\n3. Using Port Forward (Recommended for secure access):"
    echo "   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-dashboard 10254:10254"
    echo "   Then visit: http://localhost:10254/dashboard"
    
    echo -e "\n4. Metrics Endpoints:"
    echo "   Prometheus: http://${PUBLIC_IP}:10254/metrics"
    echo "   Health: http://${PUBLIC_IP}:10254/health"
}


monitor_dashboard() {
    echo "Starting dashboard monitoring..."
    
    while true; do
        clear
        echo "Dashboard Monitoring ($(date))"
        echo "----------------------------"
        
        
        echo "Pod Status:"
        kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=${RELEASE_NAME}
        
        
        echo -e "\nEndpoint Status:"
        curl -s "http://${PUBLIC_IP}:10254/health" || echo "Health check failed"
        
        
        echo -e "\nRecent Metrics:"
        curl -s "http://${PUBLIC_IP}:10254/metrics" | grep nginx_ingress_controller_requests | head -n 5
        
        sleep 10
    done
}


setup_dashboard_auth() {
    echo "Setting up dashboard authentication..."
    
    
    htpasswd -c auth admin
    kubectl create secret generic dashboard-auth \
        --from-file=auth \
        -n ${NAMESPACE}
    rm auth
    
    
    kubectl patch ingress ${RELEASE_NAME}-dashboard \
        -n ${NAMESPACE} \
        --type=json \
        -p='[{
            "op": "add",
            "path": "/metadata/annotations/nginx.ingress.kubernetes.io~1auth-type",
            "value": "basic"
        },{
            "op": "add",
            "path": "/metadata/annotations/nginx.ingress.kubernetes.io~1auth-secret",
            "value": "dashboard-auth"
        }]'
}


get_dashboard_url() {
    local username="admin"
    local password
    
    
    password=$(kubectl get secret dashboard-auth -n ${NAMESPACE} -o jsonpath="{.data.auth}" | base64 -d | cut -d: -f2)
    
    echo "Dashboard URL with credentials:"
    echo "http://${username}:${password}@${PUBLIC_IP}.nip.io/dashboard"
}


main() {
    
    set -e
    trap 'error "Script failed on line $LINENO"' ERR
    
    
    parse_args "$@"

    
    check_requirements || error "Failed to meet requirements"

    if [ "$UNINSTALL" = true ]; then
        uninstall_controller
    else
        install_controller
        
        
        test_metallb || warning "MetalLB test failed"

        
        

        
        

        
        
    fi
}


main "$@"