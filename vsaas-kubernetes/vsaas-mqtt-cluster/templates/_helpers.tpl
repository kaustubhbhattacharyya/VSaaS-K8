# templates/_helpers.tpl
{{/*
Common labels
*/}}
{{- define "vsaas-mqtt.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}