{{- define "traefik.hosts" -}}
{{- $hostString := "" }}
{{- if .hosts }}
  {{- $lastIndex := (sub (len .hosts) 1) }}
  {{- range $index, $host := .hosts }}
    {{- if eq $index $lastIndex }}
      {{- $hostString = (printf "%sHost(`%s`)" $hostString $host) }}
    {{- else }}
      {{- $hostString = (printf "%sHost(`%s`) || " $hostString $host) }}
    {{- end }}
  {{- end }}
{{- end }}
{{- if $hostString }}
  {{- printf "(%s) && " $hostString }}
{{- end }}
{{- end }}

{{- define "traefik.path" -}}
{{- if .path }}
{{- printf "PathPrefix(`%s`)" .path }}
{{- else }}
{{- fail "Path is required for every enabled HTTP service" }}
{{- end }}
{{- end }}

{{/*
  Security headers. Two Traefik Middlewares can be rendered:
    <release>-security-headers         every configured header
    <release>-security-headers-no-csp  the same minus Content-Security-Policy,
                                       for apps that send their own CSP
  Each HTTPS route picks one with <route>.securityHeaders: full | noCsp | off.
*/}}
{{- define "traefik.shRoutes" -}}
apiservice argocd auth client compliance core pgadmin routing scheduler view
{{- end }}

{{/* "true" when any header other than Content-Security-Policy is configured */}}
{{- define "traefik.shHasBase" -}}
{{- $sh := .Values.securityHeaders | default dict -}}
{{- if and (ne $sh.enabled false) (or $sh.removeServerHeaders ($sh.hsts).enabled $sh.frameOptions $sh.contentTypeOptions $sh.referrerPolicy) -}}
true
{{- end -}}
{{- end }}

{{/* "true" when the Content-Security-Policy header is configured */}}
{{- define "traefik.shHasCsp" -}}
{{- $sh := .Values.securityHeaders | default dict -}}
{{- if and (ne $sh.enabled false) $sh.frameAncestors -}}
true
{{- end -}}
{{- end }}

{{/* Validated securityHeaders mode for a route. Params: root, route */}}
{{- define "traefik.shMode" -}}
{{- $mode := (index .root.Values .route | default dict).securityHeaders | default "full" -}}
{{- if not (has $mode (list "full" "noCsp" "off")) -}}
{{- fail (printf "%s.securityHeaders must be full, noCsp or off (got %v)" .route $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end }}

{{/*
  Name of the Middleware a route should use, or empty for none.
  Params: root, route
*/}}
{{- define "traefik.shMiddlewareName" -}}
{{- $mode := include "traefik.shMode" . -}}
{{- $base := eq (include "traefik.shHasBase" .root) "true" -}}
{{- $csp := eq (include "traefik.shHasCsp" .root) "true" -}}
{{- if and (eq $mode "full") (or $base $csp) -}}
{{ .root.Release.Name }}-security-headers
{{- else if and (eq $mode "noCsp") $base -}}
{{ .root.Release.Name }}-security-headers{{ if $csp }}-no-csp{{ end }}
{{- end -}}
{{- end }}

{{/*
  Middleware reference block for an HTTPS route; empty when it gets none.
  Params: root, route
*/}}
{{- define "traefik.securityHeadersRef" -}}
{{- with include "traefik.shMiddlewareName" . -}}
middlewares:
  - name: {{ . }}
    namespace: {{ $.root.Release.Namespace }}
{{- end -}}
{{- end }}

{{/* Traefik headers Middleware spec. Params: root, csp (bool) */}}
{{- define "traefik.securityHeadersSpec" -}}
{{- $sh := .root.Values.securityHeaders -}}
headers:
  {{- if ($sh.hsts).enabled }}
  stsSeconds: {{ $sh.hsts.maxAge | int }}
  stsIncludeSubdomains: {{ $sh.hsts.includeSubdomains | default false }}
  stsPreload: {{ $sh.hsts.preload | default false }}
  {{- if $sh.hsts.force }}
  forceSTSHeader: true
  {{- end }}
  {{- end }}
  {{- with $sh.frameOptions }}
  customFrameOptionsValue: {{ . | quote }}
  {{- end }}
  {{- if and .csp $sh.frameAncestors }}
  contentSecurityPolicy: {{ printf "frame-ancestors %s" (join " " $sh.frameAncestors) | quote }}
  {{- end }}
  {{- if $sh.contentTypeOptions }}
  contentTypeNosniff: true
  {{- end }}
  {{- with $sh.referrerPolicy }}
  referrerPolicy: {{ . | quote }}
  {{- end }}
  {{- if $sh.removeServerHeaders }}
  # An empty value removes the header from the response
  customResponseHeaders:
    Server: ""
    X-Powered-By: ""
  {{- end }}
{{- end }}
