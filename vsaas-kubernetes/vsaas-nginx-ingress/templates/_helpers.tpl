# templates/_helpers.tpl

{{/* Common labels */}}
{{- define "nginx.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ $.Release.Name }}
app.kubernetes.io/environment: {{ $.Values.global.environment }}
{{- end }}

{{/* Service ports */}}
{{- define "service.port" -}}
{{- if eq .port 3010 -}}
userportal
{{- else -}}
{{- .port -}}
{{- end -}}
{{- end }}