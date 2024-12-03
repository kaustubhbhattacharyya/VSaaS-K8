# templates/_helpers.tpl
{{/* Generate basic labels */}}
{{- define "redis.labels" }}
labels:
  app.kubernetes.io/name: {{ .Release.Name }}
  app.kubernetes.io/instance: {{ .Release.Name }}
  app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}