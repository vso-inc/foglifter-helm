{{/*
Expand the name of the chart.
*/}}
{{- define "foglifter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "foglifter.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "foglifter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "foglifter.labels" -}}
helm.sh/chart: {{ include "foglifter.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- include "foglifter.selectorLabels" (dict "context" .) }}
{{- if .Values.global.labels }}
{{ toYaml .Values.global.labels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "foglifter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "foglifter.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- if .component }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "foglifter.annotations" -}}
{{- if .Values.global.annotations }}
{{ toYaml .Values.global.annotations }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "foglifter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "foglifter.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Handle image tag delineation when SHA digests are used
*/}}
{{- define "foglifter.tagDelimeter" -}}
{{- $tag := . -}}
{{- if and (contains ":" $tag) (not (contains "@" $tag)) }}
{{- "@" }}
{{- else }}
{{- ":" }}
{{- end }}
{{- end }}
