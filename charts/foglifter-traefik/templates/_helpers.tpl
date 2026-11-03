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
  "true" when any security header option is enabled.
*/}}
{{- define "traefik.securityHeadersEnabled" -}}
{{- $sh := .Values.securityHeaders | default dict -}}
{{- if and (ne $sh.enabled false) (or $sh.removeServerHeaders ($sh.hsts).enabled $sh.frameOptions $sh.frameAncestors $sh.contentTypeOptions $sh.referrerPolicy) -}}
true
{{- end -}}
{{- end }}

{{/*
  Middleware reference for HTTPS routes; empty when security headers are disabled.
*/}}
{{- define "traefik.securityHeadersRef" -}}
{{- if eq (include "traefik.securityHeadersEnabled" .) "true" -}}
middlewares:
  - name: {{ .Release.Name }}-security-headers
    namespace: {{ .Release.Namespace }}
{{- end -}}
{{- end }}
