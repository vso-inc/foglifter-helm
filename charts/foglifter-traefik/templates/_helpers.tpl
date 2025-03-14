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
