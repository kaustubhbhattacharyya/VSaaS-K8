# nginx-controller/templates/_helpers.tpl
{{/*
Create a default fully qualified app name.
*/}}
{{- define "nginx.fullname" -}}
{{- if eq .Release.Name "nginx-controller" -}}
ingress-nginx
{{- else -}}
{{- printf "%s-%s" .Release.Name "ingress-nginx" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nginx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nginx.labels" -}}
helm.sh/chart: {{ include "nginx.chart" . }}
{{ include "nginx.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.controller.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nginx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nginx.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}