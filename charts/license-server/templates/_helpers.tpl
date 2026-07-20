{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains the base name it will be used as a full name.
*/}}
{{- define "license-server.fullname" -}}
  {{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
  {{- else }}
    {{- if contains .Values.name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
    {{- else }}
      {{- printf "%s-%s" .Release.Name .Values.name | trunc 63 | trimSuffix "-" }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "license-server.chart" -}}
  {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "license-server.labels" -}}
helm.sh/chart: {{ include "license-server.chart" . }}
{{ include "license-server.selectorLabels" . }}
  {{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
  {{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: license-server
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "license-server.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the service account to use
*/}}
{{- define "license-server.serviceAccountName" -}}
  {{- if .Values.serviceAccount.create -}}
{{- default (include "license-server.fullname" .) .Values.serviceAccount.name }}
  {{- else -}}
{{- default "default" .Values.serviceAccount.name }}
  {{- end -}}
{{- end -}}
