{{/*
  Define the MONGO_URI environment variable for FogLifter microservices.
*/}}
{{- define "foglifter.mongoUri" -}}
- name: MONGO_URI
  valueFrom:
    secretKeyRef:
      {{- if and (index .Values "mongodb-kubernetes").enabled (not .Values.mongoSecretOverride) }}
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
  The internal service-mesh base URL (protocol://domain:port/path), from the
  serviceMesh block. Shared by the ConfigMap and the agent service URLs.
*/}}
{{- define "foglifter.serviceMeshUrl" -}}
{{- with .Values.serviceMesh -}}
{{- printf "%s://%s:%s%s" .protocol .domain (.port | default "80") (.path | default "/api") -}}
{{- end -}}
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
  Resolve the API secret name: the generated secret when apiSecret.create is
  true, otherwise the externally-supplied apiSecret.name (may be empty).
*/}}
{{- define "foglifter.apiSecretName" -}}
{{- if .Values.apiSecret.create -}}
{{- printf "%s-api-secret" .Release.Name -}}
{{- else -}}
{{- .Values.apiSecret.name -}}
{{- end -}}
{{- end -}}

{{/*
  Emit a Postgres DSN env var plus the password env var it references. The
  password is injected via Kubernetes $(VAR) dependent-env expansion (emitted
  first) so it never lands in Git or the ConfigMap.
  Usage: include "foglifter.postgresUri" (dict "name" "DATABASE_URI" "user" "nlq"
         "host" "postgresql" "port" 5432 "db" "nlq"
         "secret" (dict "name" "foglifter-pg-nlq" "key" "password"))
*/}}
{{- define "foglifter.postgresUri" -}}
{{- $pwVar := printf "%s_PASSWORD" (regexReplaceAll "[^A-Z0-9]" (upper .name) "_") -}}
- name: {{ $pwVar }}
  valueFrom:
    secretKeyRef:
      name: {{ .secret.name }}
      key: {{ .secret.key | default "password" }}
- name: {{ .name }}
  value: {{ printf "%s://%s:$(%s)@%s:%v/%s" (.scheme | default "postgresql") .user $pwVar .host (.port | default 5432) .db | quote }}
{{- end -}}

{{/*
  Shared Deployment for FogLifter microservices.
  Params (dict):
    root              root context (.)
    name              service name (object suffix + selector label)
    svc               the service's values block
    container         container name
    port              container port (int); "" => no PORT env, no ports, no probe port
    portEnv           bool: emit a PORT env var
    mongoUri          bool: inject MONGO_URI via foglifter.mongoUri
    apiKeyEnv         api-secret key for an APIKEY env (e.g. "CORE_APIKEY"); "" => none
    apiSecretKeys     map of {ENV_NAME: api-secret key} for extra secretKeyRef envs
    jwtSecret         bool: inject TOKEN_JWT_SECRET (optional) from the api-secret
    apiSecretEnvFrom  bool: mount the whole api-secret via envFrom
    postgres          dict for foglifter.postgresUri (emits a DSN + password env)
    trustTokenValue   TRUST_TOKEN_HASH_KEY value; empty => omitted
    volumes           raw YAML for pod volumes; empty => omitted
    volumeMounts      raw YAML for container volumeMounts; empty => omitted
    extraSecretEnvFrom raw YAML for extra envFrom secretRef entries; empty => omitted
    extraEnv          raw YAML env entries spliced before the values env loop
    probeRaw          bool: emit liveness/readiness probes verbatim (workers)
    startupProbe      bool: emit a startupProbe block
*/}}
{{- define "foglifter.deployment" -}}
{{- $ := .root -}}
{{- $svc := .svc -}}
{{- $name := .name -}}
{{- $port := .port -}}
{{- $probeRaw := .probeRaw -}}
{{- $apiSecretName := include "foglifter.apiSecretName" $ -}}
kind: Deployment
apiVersion: apps/v1
metadata:
  name: {{ $.Release.Name }}-{{ $name }}
  labels:
    app: {{ $.Release.Name }}
spec:
  replicas: {{ $svc.replicas | int }}
  selector:
    matchLabels:
      name: {{ $.Release.Name }}-{{ $name }}
  template:
    metadata:
      labels:
        name: {{ $.Release.Name }}-{{ $name }}
        app: {{ $.Release.Name }}
        {{- with $.Values.podOptions.labels }}
        {{- toYaml . | indent 8 }}
        {{- end }}
      {{- with $.Values.podOptions.annotations }}
      annotations:
        {{- toYaml . | indent 8 }}
      {{- end }}
    spec:
      serviceAccountName: {{ $.Release.Name }}-sa
      {{- with $.Values.podOptions.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $.Values.podOptions.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .volumes }}
      volumes:
        {{- . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .container }}
          {{- $delim := ":" }}
          {{- if hasPrefix "sha256:" $svc.tag }}{{- $delim = "@" }}{{- end }}
          image: {{ printf "%s%s%s%s" (default "ghcr.io/vso-inc/" $.Values.registry) $svc.repository $delim (default "latest" $svc.tag) }}
          imagePullPolicy: {{ $.Values.imagePullPolicy | quote }}
          {{- with .volumeMounts }}
          volumeMounts:
            {{- . | nindent 12 }}
          {{- end }}
          envFrom:
            - configMapRef:
                name: {{ $.Release.Name }}-cm
            {{- if and $.Values.secret.create $.Values.secret.data }}
            - secretRef:
                name: {{ $.Release.Name }}-secret
            {{- end }}
            {{- if .apiSecretEnvFrom }}
            {{- if not $apiSecretName }}{{- fail "apiSecret.name must be set if apiSecret.create is false" }}{{- end }}
            - secretRef:
                name: {{ $apiSecretName }}
            {{- end }}
            {{- with .extraSecretEnvFrom }}
            {{- . | nindent 12 }}
            {{- end }}
          env:
            {{- with .trustTokenValue }}
            - name: TRUST_TOKEN_HASH_KEY
              value: {{ . | quote }}
            {{- end }}
            {{- if .portEnv }}
            - name: PORT
              value: {{ $port | quote }}
            {{- end }}
            {{- with .apiKeyEnv }}
            - name: APIKEY
              valueFrom:
                secretKeyRef:
                  {{- if $apiSecretName }}
                  name: {{ $apiSecretName }}
                  {{- end }}
                  key: {{ . }}
            {{- end }}
            {{- if .jwtSecret }}
            - name: TOKEN_JWT_SECRET
              valueFrom:
                secretKeyRef:
                  {{- if $apiSecretName }}
                  name: {{ $apiSecretName }}
                  {{- end }}
                  key: TOKEN_JWT_SECRET
            {{- end }}
            {{- range $env, $key := .apiSecretKeys }}
            - name: {{ $env }}
              valueFrom:
                secretKeyRef:
                  {{- if $apiSecretName }}
                  name: {{ $apiSecretName }}
                  {{- end }}
                  key: {{ $key }}
            {{- end }}
            {{- with .postgres }}
            {{- include "foglifter.postgresUri" . | nindent 12 }}
            {{- end }}
            {{- if .mongoUri }}
            {{- include "foglifter.mongoUri" $ | nindent 12 }}
            {{- end }}
            {{- with .extraEnv }}
            {{- . | nindent 12 }}
            {{- end }}
            {{- with $svc.env }}
            {{- range $key, $val := . }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
            {{- end }}
            {{- with $svc.secretRef }}
            {{- range $key, $val := . }}
            - name: {{ $key }}
              valueFrom:
                secretKeyRef:
                  name: {{ $val.name }}
                  key: {{ $val.key }}
                  optional: {{ $val.optional | default false }}
            {{- end }}
            {{- end }}
          {{- if $port }}
          ports:
            - containerPort: {{ $port }}
          {{- end }}
          {{- with $svc.livenessProbe }}
          livenessProbe:
            {{- if $probeRaw }}
            {{- toYaml . | nindent 12 }}
            {{- else }}
            {{- include "foglifter.probe" (dict "probe" . "port" $port) | nindent 12 }}
            {{- end }}
          {{- end }}
          {{- with $svc.readinessProbe }}
          readinessProbe:
            {{- if $probeRaw }}
            {{- toYaml . | nindent 12 }}
            {{- else }}
            {{- include "foglifter.probe" (dict "probe" . "port" $port) | nindent 12 }}
            {{- end }}
          {{- end }}
          {{- if .startupProbe }}
          {{- with $svc.startupProbe }}
          startupProbe:
            {{- include "foglifter.probe" (dict "probe" . "port" $port) | nindent 12 }}
          {{- end }}
          {{- end }}
          {{- with $svc.resources }}
          resources:
            {{- default dict . | toYaml | nindent 12 }}
          {{- end }}
      {{- if $.Values.priorityClass.create }}
      priorityClassName: {{ $.Release.Name }}
      {{- end }}
{{- end -}}

{{/*
  Shared ClusterIP Service for FogLifter microservices.
  Params (dict): root, name, port, targetPort (defaults to port).
*/}}
{{- define "foglifter.service" -}}
{{- $ := .root -}}
kind: Service
apiVersion: v1
metadata:
  name: {{ $.Release.Name }}-{{ .name }}-svc
  labels:
    app: {{ $.Release.Name }}
spec:
  type: {{ $.Values.service.type }}
  ports:
  - port: {{ .port | int }}
    targetPort: {{ .targetPort | default .port | int }}
  selector:
    name: {{ $.Release.Name }}-{{ .name }}
{{- end -}}

{{/*
  HTTPRoute rules block, driven by gatewayAPI.httpRoute.routes.
  Params (dict): root, listener (http|https|internal), httpsEnabled, httpsRedirect.
  Each route: name, path, service (backend, defaults to name), port (defaults to
  .Values.<name>.port), enabled (default true), enabledKey (also gate on
  .Values.<key>.enabled), listeners (default all), urlRewrite.replacePrefix.
*/}}
{{- define "foglifter.httpRouteRules" -}}
{{- $ := .root -}}
{{- $listener := .listener -}}
{{- $redirect := and (eq $listener "http") .httpsEnabled .httpsRedirect -}}
rules:
{{- range $r := $.Values.gatewayAPI.httpRoute.routes }}
{{- $listeners := $r.listeners | default (list "http" "https" "internal") }}
{{- $svcOn := true }}
{{- with $r.enabledKey }}{{- $svcOn = (index $.Values .).enabled }}{{- end }}
{{- if and (ne $r.enabled false) $svcOn (has $listener $listeners) }}
  - matches:
      - path:
          type: PathPrefix
          value: {{ $r.path }}
    {{- if $redirect }}
    filters:
      - type: RequestRedirect
        requestRedirect:
          scheme: https
          statusCode: 301
    {{- else }}
    {{- with $r.urlRewrite }}
    filters:
      - type: URLRewrite
        urlRewrite:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: {{ .replacePrefix }}
    {{- end }}
    backendRefs:
      - name: {{ $.Release.Name }}-{{ $r.service | default $r.name }}-svc
        port: {{ $r.port | default (index $.Values $r.name).port | int }}
    {{- end }}
{{- end }}
{{- end }}
{{- end -}}

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
