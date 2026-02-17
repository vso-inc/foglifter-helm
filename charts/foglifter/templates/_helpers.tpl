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
  Render a Kubernetes probe, injecting the port into httpGet/tcpSocket/grpc if not already set.
*/}}
{{- define "foglifter.probe" -}}
{{- $probe := .probe | default dict -}}
{{- $port := .port -}}
{{- if $probe.httpGet }}
  {{- $httpGet := merge (dict "port" $port) $probe.httpGet }}
  {{- $probe = merge $probe (dict "httpGet" $httpGet) }}
{{- end }}
{{- if $probe.tcpSocket }}
  {{- $tcpSocket := merge (dict "port" $port) $probe.tcpSocket }}
  {{- $probe = merge $probe (dict "tcpSocket" $tcpSocket) }}
{{- end }}
{{- if $probe.grpc }}
  {{- $grpc := merge (dict "port" $port) $probe.grpc }}
  {{- $probe = merge $probe (dict "grpc" $grpc) }}
{{- end }}
{{- toYaml $probe }}
{{- end }}

{{/*
  Generate a Deployment for the given exec queue(s).
*/}}
{{- define "foglifter.execDeployments" }}
{{- $exec := required "exec must be set" .root.Values.exec }}
{{- $defaults := required "exec.defaults must be set" .root.Values.exec.defaults }}
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
        {{- with (.root.Values.podOptions).labels }}
        {{- toYaml . | indent 8 }}
        {{- end }}
      {{- with (.root.Values.podOptions).annotations }}
      annotations:
        {{- toYaml . | indent 8 }}
      {{- end }}
    spec:
      serviceAccountName: {{ .root.Release.Name }}-sa
      {{-
        $nodeSelector := .deploy.nodeSelector |
          default $defaults.nodeSelector |
          default (.root.Values.podOptions).nodeSelector
      }}
      {{- with $nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{-
        $tolerations := .deploy.tolerations |
          default $defaults.tolerations |
          default (.root.Values.podOptions).tolerations
      }}
      {{- with $tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: exec-app
          {{- $imageTagDelimiter := ":" }}
          {{- if (hasPrefix "sha256:" $exec.tag) }}
            {{- $imageTagDelimiter = "@" }}
          {{- end }}
          {{-
            $imageString := (
              printf "%s%s%s%s"
                (default "ghcr.io/vso-inc/" .root.Values.registry)
                (default "foglifter-exec-app" $exec.repository)
                ($imageTagDelimiter)
                (default "latest" $exec.tag)
            )
          }}
          image: {{ $imageString }}
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
                  optional: {{ $val.optional | default false }}
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
                  optional: {{ $val.optional | default false }}
            {{- end }}
            {{- end }}
            {{- end }}
          {{- with $exec.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $exec.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $exec.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- if .deploy.resources }}
            {{ .deploy.resources | toYaml | nindent 12 }}
            {{- else }}
            {{- default dict $defaults.resources | toYaml | nindent 12 }}
            {{- end }}
      {{- $selfAntiAffinity := (.deploy.antiAffinity).self | default ($defaults.antiAffinity).self }}
      {{- $customAntiAffinity := or (.deploy.antiAffinity).custom ($defaults.antiAffinity).custom }}
      {{- if or $selfAntiAffinity $customAntiAffinity }}
      affinity:
        podAntiAffinity:
          {{- if $selfAntiAffinity }}
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
          {{- if $customAntiAffinity }}
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
