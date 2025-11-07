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

{{/*
  Generate a Deployment for the given exec queue(s).
*/}}
{{- define "foglifter.execDeployments" }}
{{- $defaults := .root.Values.exec.defaults }}
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: {{ .root.Release.Name }}-exec-{{ .deployName }}
  labels:
    app: {{ .root.Release.Name }}
spec:
  replicas: {{ default $defaults.replicas .deploy.replicas | int }}
  selector:
    matchLabels:
      name: {{ .root.Release.Name }}-exec
      controller: {{ .deployName }}
  template:
    metadata:
      labels:
        name: {{ .root.Release.Name }}-exec
        controller: {{ .deployName }}
        app: {{ .root.Release.Name }}
    spec:
      serviceAccountName: {{ .root.Release.Name }}-sa
      containers:
        - name: exec-app
          {{- $imageTagDelimiter := ":" }}
          {{- if (hasPrefix "sha256:" $defaults.tag) }}
            {{- $imageTagDelimiter = "@" }}
          {{- end }}
          image: "{{ default "ghcr.io/vso-inc/" .root.Values.registry }}{{ default "foglifter-exec-app" $defaults.repository }}{{ $imageTagDelimiter }}{{ default "latest" $defaults.tag }}"
          imagePullPolicy: "{{ default "Always" .root.Values.imagePullPolicy }}"
          envFrom:
            - configMapRef:
                name: {{ .root.Release.Name }}-cm
            {{- if and (ne (.root.Values.secret).create false) (.root.Values.secret).data }}
            - secretRef:
                name: {{ .root.Release.Name }}-secret
            {{- end }}
          env:
            - name: APIKEY
              valueFrom:
                secretKeyRef:
                  {{- if (.root.Values.apiSecret).create }}
                  name: {{ .root.Release.Name }}-api-secret
                  {{- else if (.root.Values.apiSecret).name }}
                  name: {{ .root.Values.apiSecret.name }}
                  {{- end }}
                  key: EXECUTOR_APIKEY
            - name: NODE_OPTIONS
              {{- $options := "" }}
              {{- if (.deploy.env).NODE_OPTIONS }}
              {{- $options = .deploy.env.NODE_OPTIONS | trim }}
              {{- else if ($defaults.env).NODE_OPTIONS }}
              {{- $options = $defaults.env.NODE_OPTIONS | trim }}
              {{- end }}
              {{- if ((.deploy.resources).limits).memory }}
              {{- $moss := regexReplaceAll "[^0-9]+" ((.deploy.resources).limits).memory "" }}
              value: {{ printf "--max-old-space-size=%s %s" $moss $options | trim }}
              {{- else }}
              value: {{ $options | default "" | trim | quote }}
              {{- end }}
            {{- include "foglifter.mongoUri" .root | nindent 12 }}
            - name: QUEUES
              value: {{ join "," .deploy.queues | quote }}
            {{- if $defaults.env }}
            {{- range $key, $val := omit $defaults.env "NODE_OPTIONS" }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
            {{- end }}
            {{- if .deploy.env }}
            {{- range $key, $val := omit .deploy.env "NODE_OPTIONS" }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
            {{- end }}
            {{- if $defaults.secretRef }}
            {{- with $defaults.secretRef }}
            {{- range $key, $val := . }}
            - name: {{ $key }}
              valueFrom:
                secretKeyRef:
                  name: {{ $val.name }}
                  key: {{ $val.key }}
            {{- end }}
            {{- end }}
            {{- end }}
            {{- if .deploy.secretRef }}
            {{- with .deploy.secretRef }}
            {{- range $key, $val := . }}
            - name: {{ $key }}
              valueFrom:
                secretKeyRef:
                  name: {{ $val.name }}
                  key: {{ $val.key }}
            {{- end }}
            {{- end }}
            {{- end }}
          resources:
            {{- if .deploy.resources }}
            {{ .deploy.resources | toYaml | nindent 12 }}
            {{- else }}
            {{- default dict $defaults.resources | toYaml | nindent 12 }}
            {{- end }}
      {{- if or (or ($defaults.antiAffinity).self ($defaults.antiAffinity).custom) (.deploy.antiAffinity).custom }}
      affinity:
        podAntiAffinity:
          {{- if ($defaults.antiAffinity).self }}
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: name
                    operator: In
                    values:
                      - {{ .root.Release.Name }}-exec
                  - key: controller
                    operator: In
                    values:
                      - {{ .deployName }}
              topologyKey: kubernetes.io/hostname
          {{- end }}
          {{- if or ($defaults.antiAffinity).custom (.deploy.antiAffinity).custom }}
          preferredDuringSchedulingIgnoredDuringExecution:
            {{- if ($defaults.antiAffinity).custom }}
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    {{- toYaml $defaults.antiAffinity.custom | nindent 20 }}
                topologyKey: kubernetes.io/hostname
            {{- end }}
            {{- if (.deploy.antiAffinity).custom }}
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    {{- toYaml .deploy.antiAffinity.custom | nindent 20 }}
                topologyKey: kubernetes.io/hostname
            {{- end }}
          {{- end }}
      {{- end }}
      {{- if (.root.Values.priorityClass).create }}
      priorityClassName: {{ .root.Release.Name }}
      {{- end }}
{{- end }}
