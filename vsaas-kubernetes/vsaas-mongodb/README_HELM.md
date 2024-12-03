## Helm Chart Details

### Chart Structure
```
vsaas-mongodb/
├── Chart.yaml                 # Chart metadata and version info
├── values.yaml               # Default configuration values
├── templates/                # Kubernetes manifest templates
│   ├── NOTES.txt            # Chart usage notes
│   ├── _helpers.tpl         # Template helpers
│   ├── configmap.yaml       # MongoDB configuration
│   ├── secret.yaml          # Credentials
│   ├── pv.yaml              # Persistent Volume
│   ├── pvc.yaml            # Persistent Volume Claim
│   ├── service.yaml        # Service definition
│   └── statefulset.yaml    # MongoDB StatefulSet
└── charts/                  # Dependent charts (if any)
```

### Chart.yaml
```yaml
apiVersion: v2
name: vsaas-mongodb
description: MongoDB Helm chart for VSaaS
version: 0.1.0
appVersion: "5.0"
```

### values.yaml
```yaml
# Default values for vsaas-mongodb
nameOverride: ""
fullnameOverride: "mongodb"

namespace: vsaas-dev

mongodb:
  image: mongo:5.0
  imagePullPolicy: Always
  storage:
    size: 10Gi
    path: /data/mongodb
  auth:
    username: root
    password: root@central1234
  nodeSelector:
    hostname: vsaas-workernode-3
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "2Gi"

service:
  port: 27017
  targetPort: 27017
  nodePort: 30017
```

### Helm Commands

#### Installation
```bash
# Install chart
helm install vsaas-mongodb . \
  -n vsaas-dev \
  --create-namespace

# Install with custom values
helm install vsaas-mongodb . \
  -n vsaas-dev \
  -f custom-values.yaml

# Install with value overrides
helm install vsaas-mongodb . \
  -n vsaas-dev \
  --set mongodb.storage.size=20Gi \
  --set mongodb.auth.password=custom_password
```

#### Upgrade
```bash
# Upgrade chart
helm upgrade vsaas-mongodb . \
  -n vsaas-dev

# Upgrade with value changes
helm upgrade vsaas-mongodb . \
  -n vsaas-dev \
  --set mongodb.image=mongo:5.1

# Rollback to previous release
helm rollback vsaas-mongodb 1 -n vsaas-dev
```

#### Chart Management
```bash
# List releases
helm list -n vsaas-dev

# Get release status
helm status vsaas-mongodb -n vsaas-dev

# Get release history
helm history vsaas-mongodb -n vsaas-dev

# Get release values
helm get values vsaas-mongodb -n vsaas-dev
```

#### Debug and Testing
```bash
# Test template rendering
helm template vsaas-mongodb . -n vsaas-dev

# Debug installation
helm install vsaas-mongodb . \
  -n vsaas-dev \
  --debug \
  --dry-run

# Verify chart
helm lint .
```

### Custom Values Example
```yaml
# custom-values.yaml
mongodb:
  storage:
    size: 50Gi
  resources:
    requests:
      memory: "2Gi"
    limits:
      memory: "4Gi"
  nodeSelector:
    custom-label: value

service:
  nodePort: 31017
```

### Template Helpers (_helpers.tpl)
```yaml
{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mongodb.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mongodb.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "mongodb.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

### Advanced Helm Usage

#### Conditional Template Example
```yaml
{{- if .Values.mongodb.metrics.enabled }}
# Metrics Service
apiVersion: v1
kind: Service
metadata:
  name: {{ include "mongodb.fullname" . }}-metrics
  labels:
    {{- include "mongodb.labels" . | nindent 4 }}
spec:
  ports:
    - port: {{ .Values.mongodb.metrics.port }}
      targetPort: metrics
  selector:
    {{- include "mongodb.selectorLabels" . | nindent 4 }}
{{- end }}
```

#### Using Secrets
```yaml
# templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "mongodb.fullname" . }}
  labels:
    {{- include "mongodb.labels" . | nindent 4 }}
type: Opaque
stringData:
  mongodb-root-username: {{ .Values.mongodb.auth.username }}
  mongodb-root-password: {{ .Values.mongodb.auth.password }}
```

#### Resource Management
```yaml
# templates/statefulset.yaml snippet
resources:
  {{- toYaml .Values.mongodb.resources | nindent 12 }}
```

### Helm Best Practices

1. **Values Organization**
   - Use structured values
   - Provide defaults
   - Document values
   - Use consistent naming

2. **Template Organization**
   - Use helpers for common elements
   - Break down complex templates
   - Use consistent indentation
   - Add helpful comments

3. **Security**
   - Use secrets for sensitive data
   - Set resource limits
   - Configure RBAC properly
   - Use secure defaults

4. **Maintenance**
   - Version your chart
   - Document changes
   - Test thoroughly
   - Use CI/CD pipelines

### Common Issues and Solutions

1. **Template Rendering Issues**
```bash
# Debug template rendering
helm template . --debug

# Verify syntax
helm lint .
```

2. **Resource Creation Issues**
```bash
# Check status
helm status vsaas-mongodb -n vsaas-dev

# Get detailed description
kubectl describe pod -n vsaas-dev -l app=vsaas-mongodb
```

3. **Upgrade Issues**
```bash
# Rollback to previous version
helm rollback vsaas-mongodb 1 -n vsaas-dev

# Force resource updates
helm upgrade vsaas-mongodb . \
  -n vsaas-dev \
  --force
```