{{/*
Expand the name of the chart.
*/}}
{{- define "polars.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "polars.fullname" -}}
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
{{- define "polars.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "polars.labels" -}}
helm.sh/chart: {{ include "polars.chart" . }}
{{ include "polars.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "polars.selectorLabels" -}}
app.kubernetes.io/name: {{ include "polars.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels as comma-separated string for environment variables
*/}}
{{- define "polars.selectorLabelsComma" -}}
app.kubernetes.io/name={{ include "polars.name" . }},app.kubernetes.io/instance={{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "polars.serviceAccountName" -}}
{{- if .Values.worker.serviceAccount.create }}
{{- default (include "polars.fullname" .) .Values.worker.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.worker.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "polars.worker.serviceAccountName" -}}
{{- default "default" .Values.worker.serviceAccount.name }}
{{- end }}


{{/*
Create worker fullname
*/}}
{{- define "polars.worker.fullname" -}}
{{- printf "%s-worker" (include "polars.fullname" .) }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "polars.scheduler.serviceAccountName" -}}
{{- default "default" .Values.scheduler.serviceAccount.name }}
{{- end }}

{{/*
Create opentelemetry-collector fullname
*/}}
{{- define "polars.opentelemetry-collector.fullname" -}}
{{- printf "%s-opentelemetry-collector" (include "polars.fullname" .) }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "polars.opentelemetry-collector.serviceAccountName" -}}
{{- default "default" .Values.opentelemetryCollector.serviceAccount.name }}
{{- end }}

{{/*
Create scheduler internal fullname
*/}}
{{- define "polars.scheduler-internal.fullname" -}}
{{- printf "%s-scheduler-internal" (include "polars.fullname" .) }}
{{- end }}

{{/*
Create scheduler fullname
*/}}
{{- define "polars.scheduler.fullname" -}}
{{- printf "%s-scheduler" (include "polars.fullname" .) }}
{{- end }}

{{/*
Create observatory fullname
*/}}
{{- define "polars.observatory.fullname" -}}
{{- printf "%s-observatory" (include "polars.fullname" .) }}
{{- end }}

{{/*
Create worker headless service fullname
*/}}
{{- define "polars.worker-headless.fullname" -}}
{{- printf "%s-worker-headless" (include "polars.fullname" .) }}
{{- end }}

{{/*
Cluster ID
*/}}
{{- define "polars.clusterId" -}}
{{- if .Values.clusterId }}
{{- .Values.clusterId | quote }}
{{- else }}
{{- printf "%s/%s" .Release.Namespace .Release.Name | quote }}
{{- end }}
{{- end }}