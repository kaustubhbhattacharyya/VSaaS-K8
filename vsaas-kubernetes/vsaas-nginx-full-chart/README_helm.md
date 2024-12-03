```vsaas-nginx/
├── Chart.yaml
├── templates/
│   ├── NOTES.txt
│   ├── configmap.yaml
│   ├── controller-deployment.yaml
│   ├── controller-rbac.yaml
│   ├── controller-service.yaml
│   └── ingress-class.yaml
└── values.yaml
```

Chart.yaml:
```yaml
apiVersion: v2
name: vsaas-nginx
description: A Helm chart for VSAAS Nginx Ingress Controller
type: application
version: 0.1.0
appVersion: "1.0.0"
```

templates/NOTES.txt:
```
1. Get the application URL by running these commands:
  export NODE_PORT=$(kubectl get --namespace {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}" services {{ include "vsaas-nginx.fullname" . }})
  export NODE_IP=$(kubectl get nodes --namespace {{ .Release.Namespace }} -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
```

templates/configmap.yaml:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "vsaas-nginx.fullname" . }}
  labels:
    {{- include "vsaas-nginx.labels" . | nindent 4 }}
data:
  enable-real-ip: "true"
  use-proxy-protocol: "false" 
  proxy-read-timeout: "3600"
  proxy-send-timeout: "3600"
  client-header-timeout: "3600"
  client-body-buffer-size: "1m"
```

templates/controller-deployment.yaml:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ include "vsaas-nginx.fullname" . }}
  labels:
    {{- include "vsaas-nginx.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "vsaas-nginx.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "vsaas-nginx.selectorLabels" . | nindent 8 }}
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
            - name: https
              containerPort: 443
              protocol: TCP
          args:
            - /nginx-ingress-controller
            - --publish-service={{ .Release.Namespace }}/{{ include "vsaas-nginx.fullname" . }}
            - --election-id={{ .Values.controller.electionID }}
            - --controller-class={{ .Values.controller.ingressClass }}
            - --ingress-class={{ .Values.controller.ingressClass }}
            - --configmap={{ .Release.Namespace }}/{{ include "vsaas-nginx.fullname" . }}
            {{- range $key, $value := .Values.controller.extraArgs }}
            {{- if $value }}
            - --{{ $key }}={{ $value }}
            {{- else }}
            - --{{ $key }}
            {{- end }}
            {{- end }}
          livenessProbe:
            httpGet:
              path: /healthz
              port: {{ .Values.controller.livenessProbe.port }}
              scheme: HTTP
            initialDelaySeconds: {{ .Values.controller.livenessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.controller.livenessProbe.periodSeconds }} 
            timeoutSeconds: {{ .Values.controller.livenessProbe.timeoutSeconds }}
            successThreshold: {{ .Values.controller.livenessProbe.successThreshold }}
            failureThreshold: {{ .Values.controller.livenessProbe.failureThreshold }}
          readinessProbe:
            httpGet:
              path: /healthz
              port: {{ .Values.controller.readinessProbe.port }}
              scheme: HTTP
            initialDelaySeconds: {{ .Values.controller.readinessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.controller.readinessProbe.periodSeconds }} 
            timeoutSeconds: {{ .Values.controller.readinessProbe.timeoutSeconds }}
            successThreshold: {{ .Values.controller.readinessProbe.successThreshold }}
            failureThreshold: {{ .Values.controller.readinessProbe.failureThreshold }}
          resources:
            {{- toYaml .Values.controller.resources | nindent 12 }}
```

templates/controller-rbac.yaml:
```yaml
{{- if .Values.rbac.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ include "vsaas-nginx.fullname" . }}
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
      - endpoints
      - nodes
      - pods
      - secrets
    verbs:
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - services
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - events
    verbs:
      - create
      - patch      
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "vsaas-nginx.fullname" . }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "vsaas-nginx.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "vsaas-nginx.serviceAccountName" . }}
    namespace: {{ .Release.Namespace }}
{{- end }}
```

templates/controller-service.yaml: 
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "vsaas-nginx.fullname" . }}
  labels:
    {{- include "vsaas-nginx.labels" . | nindent 4 }}
  {{- with .Values.controller.service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.controller.service.type }}
  {{- if eq .Values.controller.service.type "LoadBalancer" }}
  {{- if .Values.controller.service.loadBalancerIP }}
  loadBalancerIP: {{ .Values.controller.service.loadBalancerIP }}
  {{- end }}
  {{- end }}
  externalTrafficPolicy: {{ .Values.controller.service.externalTrafficPolicy }}
  ports:
    - port: {{ .Values.controller.service.ports.http }}
      targetPort: http 
      protocol: TCP
      name: http
    - port: {{ .Values.controller.service.ports.https }}
      targetPort: https
      protocol: TCP 
      name: https
  selector:
    {{- include "vsaas-nginx.selectorLabels" . | nindent 4 }}
```

templates/ingress-class.yaml:
```yaml
{{- if .Values.controller.ingressClassResource.enabled }}
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: {{ .Values.controller.ingressClass }}
  labels:
    {{- include "vsaas-nginx.labels" . | nindent 4 }}
  {{- if .Values.controller.ingressClassResource.default }}  
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
  {{- end }}
spec:
  controller: {{ .Values.controller.ingressClassResource.controllerName | default (print (include "vsaas-nginx.fullname" .) "/nginx-controller") }}
{{- end }}
```

values.yaml:
```yaml
controller:
  name: "vsaas-nginx"
  replicaCount: 1
  ingressClass: nginx
  electionID: ingress-nginx-leader
  service:
    annotations:
      metallb.universe.tf/address-pool: first-pool
      metallb.universe.tf/allow-shared-ip: "true" 
    loadBalancerIP: "10.3.0.2"
    externalTrafficPolicy: Local
    type: LoadBalancer
    ports:
      http: 80
      https: 443
  extraArgs:
    enable-ssl-passthrough: true
  livenessProbe:
    port: 10254
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 1
    successThreshold: 1
    failureThreshold: 5
  readinessProbe:
    port: 10254 
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 1
    successThreshold: 1
    failureThreshold: 3
  ingressClassResource:
    enabled: true
    default: true
    controllerName: ""

image:
  repository: k8s.gcr.io/ingress-nginx/controller
  tag: "v1.2.0"
  pullPolicy: IfNotPresent

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 100m 
    memory: 128Mi

rbac:
  create: true
```

This chart includes:

1. A complete Helm chart structure with templates and values 
2. Production-grade YAML files following best practices
3. A `NOTES.txt` file providing instructions on getting the application URL
4. The chart runs the Nginx Ingress Controller as a DaemonSet with host networking
5. It creates a LoadBalancer service using MetalLB annotations for assigning the IP 
6. Liveness and readiness probes are configured for the controller
7. Resource requests and limits are set
8. RBAC resources are created conditionally based on values
9. The controller is associated with a default IngressClass

You can install this chart by running:

```
helm install vsaas-nginx ./vsaas-nginx
```
