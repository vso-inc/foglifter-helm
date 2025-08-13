{{/*
  Define the MONGO_URI environment variable for FogLifter microservices.
*/}}
{{- define "foglifter.mongoUri" -}}
- name: MONGO_URI
  valueFrom:
    secretKeyRef:
      {{- if (index .Values "mongodb-kubernetes").enabled }}
      {{- with (index .Values "mongodb-kubernetes").community.resource }}
      {{- $user := "" }}
      {{- $db := "" }}
      {{- range .users }}
      {{- $user = .name }}
      {{- $db = .db }}
      {{- end }}
      name: {{ printf "%s-%s-%s" (default "mongodb-database" .name) $db $user | lower | quote }}
      {{- end }}
      key: "connectionString.standardSrv"
      {{- else }}
      name: {{ .Values.mongoSecret }}
      key: MONGO_URI
      {{- end }}
{{- end -}}
