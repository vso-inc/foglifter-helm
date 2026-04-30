{{/*
Standard chart-name helpers.
*/}}
{{- define "foglifter-headlamp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "foglifter-headlamp.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "foglifter-headlamp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "foglifter-headlamp.labels" -}}
helm.sh/chart: {{ include "foglifter-headlamp.chart" . }}
app.kubernetes.io/name: {{ include "foglifter-headlamp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: foglifter-headlamp
{{- end -}}

{{/*
Stable name for the redirect-slash Middleware. Used both as the resource name
and (with the release namespace prefix) as the value of the
`traefik.ingress.kubernetes.io/router.middlewares` annotation on the Ingress.
*/}}
{{- define "foglifter-headlamp.redirectMiddlewareName" -}}
{{- printf "%s-redirect-slash" (include "foglifter-headlamp.fullname" .) -}}
{{- end -}}

{{- define "foglifter-headlamp.redirectMiddlewareAnnotation" -}}
{{- printf "%s-%s@kubernetescrd" .Release.Namespace (include "foglifter-headlamp.redirectMiddlewareName" .) -}}
{{- end -}}

{{/*
Backend Service name for Headlamp. Mirrors the Headlamp sub-chart's fullname
template: `<release>-headlamp` when the chart name is not already a substring
of the release name, otherwise just `<release>`. The sub-chart names its
Service after this fullname; the same logic is reproduced here so the
Ingress / HTTPRoute backend reference resolves regardless of release name.
*/}}
{{- define "foglifter-headlamp.headlampServiceName" -}}
{{- $name := "headlamp" -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
