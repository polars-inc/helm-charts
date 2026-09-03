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
Create the name of the service account to use
*/}}
{{- define "polars.tests.serviceAccountName" -}}
{{- default "default" .Values.tests.serviceAccount.name }}
{{- end }}

{{/*
Create tests fullname
*/}}
{{- define "polars.tests.fullname" -}}
  {{- printf "%s-tests" (include "polars.fullname" .) }}
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
Shuffle data shared PVC name
*/}}
{{- define "polars.shuffleDataPvcName" -}}
  {{- if .Values.shuffleData.sharedPersistentVolumeClaim.existingClaimName }}
{{- .Values.shuffleData.sharedPersistentVolumeClaim.existingClaimName }}
  {{- else }}
    {{- printf "%s-polars-shuffle-data" (include "polars.fullname" .) }}
  {{- end }}
{{- end }}

{{/*
Checkpoint data shared PVC name
*/}}
{{- define "polars.checkpointDataPvcName" -}}
  {{- if .Values.checkpointData.sharedPersistentVolumeClaim.existingClaimName }}
{{- .Values.checkpointData.sharedPersistentVolumeClaim.existingClaimName }}
  {{- else }}
    {{- printf "%s-polars-checkpoint-data" (include "polars.fullname" .) }}
  {{- end }}
{{- end }}

{{/*
Observatory data PVC name
*/}}
{{- define "polars.observatoryDataPvcName" -}}
  {{- if .Values.observatory.persistentVolumeClaim.existingClaimName }}
{{- .Values.observatory.persistentVolumeClaim.existingClaimName }}
  {{- else }}
    {{- printf "%s-polars-observatory-data" (include "polars.fullname" .) }}
  {{- end }}
{{- end }}

{{/*
On Prem License Certificate Volume
*/}}
{{- define "polars.onPremLicenseCertificatePvcName" -}}
  {{- if .Values.license.onPrem.licenseData.existingClaimName }}
{{- .Values.license.onPrem.licenseData.existingClaimName }}
  {{- else }}
    {{- printf "%s-on-prem-license-certificate" (include "polars.fullname" .) }}
  {{- end }}
{{- end }}

{{/*
Validates license config. Fails on:
- Both On-Prem and On-Prem enterprise fields set simultaneously
- Partial On-Prem (missing clientId, clientSecret, or workspaceId)
- Partial On-Prem enterprise fields (secretName set but secretProperty missing, or vice versa)
Setting `license=null` removes the license check from the helm chart (still enforced in the release artifacts).
*/}}
{{- define "polars.validateLicense" -}}
  {{- if not (kindIs "invalid" .Values.license) -}}
    {{- $hasOnPrem := .Values.license.onPrem.enabled -}}
    {{- $hasOnPremEnterprise := .Values.license.onPremEnterprise.enabled -}}
    {{- $hasLicenseServer := .Values.license.licenseServer.enabled -}}

    {{- $enabledCount := 0 -}}
    {{- if $hasOnPrem }}{{- $enabledCount = add1 $enabledCount }}{{- end -}}
    {{- if $hasOnPremEnterprise }}{{- $enabledCount = add1 $enabledCount }}{{- end -}}
    {{- if $hasLicenseServer }}{{- $enabledCount = add1 $enabledCount }}{{- end -}}

    {{- if ne $enabledCount 1 -}}
      {{- fail "License error: exactly one of .Values.license.onPrem.enabled, .Values.license.onPremEnterprise.enabled or .Values.license.licenseServer.enabled must be true" -}}
    {{- end -}}

    {{- if $hasOnPrem -}}
      {{- if not .Values.license.onPrem.clientId -}}
        {{- fail "License error: .Values.license.onPrem.clientId is required when using Polars On-Prem license" -}}
      {{- end -}}
      {{- if not .Values.license.onPrem.clientSecret -}}
        {{- fail "License error: .Values.license.onPrem.clientSecret is required when using Polars On-Prem license" -}}
      {{- end -}}
      {{- if not .Values.license.onPrem.workspaceId -}}
        {{- fail "License error: .Values.license.onPrem.workspaceId is required when using Polars On-Prem license" -}}
      {{- end -}}
    {{- end -}}

    {{- if $hasOnPremEnterprise -}}
      {{- if not .Values.acceptEula }}
        {{ fail "EULA not accepted. Please refer to the EULA as forwarded by Polars together with your license." }}
      {{- end }}
      {{- if not .Values.license.onPremEnterprise.secretName -}}
        {{- fail "License error: .Values.license.onPremEnterprise.secretName is required when using Polars On-Prem Enterprise license" -}}
      {{- end -}}
      {{- if not .Values.license.onPremEnterprise.secretProperty -}}
        {{- fail "License error: .Values.license.onPremEnterprise.secretProperty is required when using Polars On-Prem Enterprise license" -}}
      {{- end -}}
    {{- end -}}

    {{- if $hasLicenseServer -}}
      {{- if not .Values.license.licenseServer.uri -}}
        {{- fail "License error: .Values.license.licenseServer.uri is required when using the Polars license server" -}}
      {{- end -}}
    {{- end -}}
  {{- end }}
{{- end -}}


{{- define "polars.isOnPremLicense" -}}
  {{- include "polars.validateLicense" . -}}
  {{- if ((.Values.license).onPrem).enabled -}}true{{- end -}}
{{- end -}}


{{- define "polars.isOnPremEnterpriseLicense" -}}
  {{- include "polars.validateLicense" . -}}
  {{- if ((.Values.license).onPremEnterprise).enabled -}}true{{- end -}}
{{- end -}}


{{- define "polars.isLicenseServerLicense" -}}
  {{- include "polars.validateLicense" . -}}
  {{- if ((.Values.license).licenseServer).enabled -}}true{{- end -}}
{{- end -}}

{{/*
Renders a single env var value, supporting both plain strings and valueFrom objects.
Usage: {{ include "polars.envVarValue" .Values.license.onPrem.clientId }}
*/}}
{{- define "polars.envVarValue" -}}
  {{- if kindIs "string" . }}
value: {{ . | quote }}
  {{- else }}
{{ toYaml . }}
  {{- end }}
{{- end }}

{{/*
Cluster ID
*/}}
{{- define "polars.clusterId" -}}
  {{- if .Values.clusterId }}
{{- .Values.clusterId }}
  {{- else }}
    {{- printf "%s/%s" .Release.Namespace .Release.Name }}
  {{- end }}
{{- end }}

{{/*
Kubernetes cluster DNS domain
*/}}
{{- define "polars.clusterDomain" -}}
{{- default "cluster.local" .Values.clusterDomain }}
{{- end }}

{{/*
Create temporary storage fullname
*/}}
{{- define "polars.temporaryStorage.fullname" -}}
  {{- printf "%s-temporary-storage" (include "polars.fullname" .) }}
{{- end }}


{{/*
Whether anonymous results is enabled
*/}}
{{- define "polars.isAnonymousResultsEnabled" -}}
  {{- if or .Values.anonymousResults.s3.enabled .Values.anonymousResults.temporaryStorage.enabled .Values.anonymousResults.abs.enabled .Values.anonymousResults.gcs.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Whether any remote shuffle is enabled
*/}}
{{- define "polars.isRemoteShuffleEnabled" -}}
  {{- if or .Values.shuffleData.s3.enabled .Values.shuffleData.abs.enabled .Values.shuffleData.gcs.enabled .Values.shuffleData.sharedFilesystem.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Whether a checkpoint location is configured
*/}}
{{- define "polars.isCheckpointLocationEnabled" -}}
  {{- if or .Values.checkpointData.s3.enabled .Values.checkpointData.abs.enabled .Values.checkpointData.gcs.enabled .Values.checkpointData.sharedFilesystem.enabled .Values.checkpointData.sharedPersistentVolumeClaim.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Default topology spread
*/}}
{{- define "polars.defaultTopologySpreadConstraints" -}}
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Python scheduler URI expression
*/}}
{{- define "polars.notes.schedulerUri" -}}
  {{- if contains "NodePort" .Values.scheduler.services.scheduler.type -}}
"http://"+os.environ["SCHEDULER_NODE_IP"]+":"+os.environ["SCHEDULER_NODE_PORT"]
  {{- else if contains "LoadBalancer" .Values.scheduler.services.scheduler.type -}}
"http://"+os.environ["SCHEDULER_SERVICE_IP"]+":5051"
  {{- else if contains "ClusterIP" .Values.scheduler.services.scheduler.type -}}
"http://127.0.0.1:5051"
  {{- end -}}
{{- end }}

{{/*
Python observatory URI expression
*/}}
{{- define "polars.notes.observatoryUri" -}}
  {{- if contains "NodePort" .Values.scheduler.services.observatory.type -}}
"http://"+os.environ["OBSERVATORY_NODE_IP"]+":"+os.environ["OBSERVATORY_NODE_PORT"]
  {{- else if contains "LoadBalancer" .Values.scheduler.services.observatory.type -}}
"http://"+os.environ["OBSERVATORY_SERVICE_IP"]+":5051"
  {{- else if contains "ClusterIP" .Values.scheduler.services.observatory.type -}}
"http://127.0.0.1:3001"
  {{- end -}}
{{- end }}

{{/*
Python ClusterContext line for NOTES.txt
*/}}
{{- define "polars.notes.clusterContext" -}}
ctx = pc.ClusterContext(uri={{ include "polars.notes.schedulerUri" . }}, observatory=pc.ClientOptions(uri={{ include "polars.notes.observatoryUri" . }}))
{{- end }}

{{/*
Verify that .Values.runtime.composed.polarsExtras contains cloudpickle and return the entire string
*/}}
{{- define "polars.runtimeComposedExtras" -}}
  {{- if not (contains "cloudpickle" .Values.runtime.composed.polarsExtras) -}}
    {{- fail ".Values.runtime.composed.polarsExtras must include cloudpickle" }}
  {{- end }}
{{ .Values.runtime.composed.polarsExtras }}
{{- end }}

{{/*
Validate runtime
*/}}
{{- define "polars.validateRuntime" -}}
  {{- if and .Values.runtime.composed.enabled .Values.runtime.prebuilt.enabled }}
    {{- fail "Runtime error: .Values.runtime.composed.enabled and .Values.runtime.prebuilt.enabled are mutually exclusive" }}
  {{- end }}
  {{- if and (not .Values.runtime.composed.enabled) (not .Values.runtime.prebuilt.enabled) }}
    {{- fail "Runtime error: either .Values.runtime.composed.enabled or .Values.runtime.prebuilt.enabled is required" }}
  {{- end }}
{{- end }}

{{/*
Verify that we're using composed runtime
*/}}
{{- define "polars.isRuntimeComposed" -}}
  {{- include "polars.validateRuntime" . -}}
  {{- if .Values.runtime.composed.enabled -}}true{{- end -}}
{{- end }}

{{/*
Verify that we're using prebuilt runtime
*/}}
{{- define "polars.isRuntimePrebuilt" -}}
  {{- include "polars.validateRuntime" . -}}
  {{- if .Values.runtime.prebuilt.enabled -}}true{{- end -}}
{{- end }}

{{/*
Validates scaling config. Fails on:
- maxReplicas set below minReplicas
- workersPerQuery.default unset, which the scheduler rejects at startup
*/}}
{{- define "polars.validateScaling" -}}
  {{- if .Values.scaling.enabled -}}
    {{- $maxReplicas := include "polars.scaling.maxReplicas" . -}}
    {{- if and $maxReplicas (lt ($maxReplicas | int) (.Values.scaling.minReplicas | int)) -}}
      {{- fail "Scaling error: .Values.scaling.maxReplicas must be greater than or equal to .Values.scaling.minReplicas" -}}
    {{- end -}}
    {{- if kindIs "invalid" .Values.workersPerQuery.default -}}
      {{- fail "Scaling error: .Values.workersPerQuery.default must be set when .Values.scaling.enabled is true, since it is the capacity each query requests from the autoscaler" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Whether autoscaling of the worker Deployment is enabled
*/}}
{{- define "polars.isAutoscalingEnabled" -}}
  {{- include "polars.validateScaling" . -}}
  {{- if .Values.scaling.enabled -}}true{{- end -}}
{{- end -}}

{{/*
Maximum number of worker replicas for autoscaling, as a string.
Empty when unset, which means unbounded.
*/}}
{{- define "polars.scaling.maxReplicas" -}}
  {{- if not (kindIs "invalid" .Values.scaling.maxReplicas) }}{{ .Values.scaling.maxReplicas }}{{ end -}}
{{- end -}}

{{/*
Name shared by the scaling Role and RoleBinding.
*/}}
{{- define "polars.scaling.rbacName" -}}
  {{- printf "%s-scaling" (include "polars.scheduler.fullname" .) -}}
{{- end -}}

{{/*
Workers a query uses when it requests no count, as a string. Falls back to the
worker replica count for a fixed-size cluster; empty when autoscaling is enabled
and no default is configured, which polars.validateScaling rejects.
Reads .Values.scaling.enabled directly to avoid recursing through validation.
*/}}
{{- define "polars.workersPerQuery.default" -}}
  {{- include "polars.validateWorkersPerQuery" . -}}
  {{- if not (kindIs "invalid" .Values.workersPerQuery.default) }}{{ .Values.workersPerQuery.default }}
  {{- else if not .Values.scaling.enabled }}{{ .Values.worker.deployment.replicaCount }}{{ end -}}
  {{- end -}}

  {{/*
  Upper bound on workers per query, as a string. Empty when unset.
  */}}
  {{- define "polars.workersPerQuery.max" -}}
    {{- if not (kindIs "invalid" .Values.workersPerQuery.max) }}{{ .Values.workersPerQuery.max }}{{ end -}}
  {{- end -}}

  {{/*
  Fails when the removed .Values.requireFreeWorkers is still set, pointing at the
  .Values.workersPerQuery migration.
  */}}
  {{- define "polars.validateWorkersPerQuery" -}}
    {{- if not (kindIs "invalid" .Values.requireFreeWorkers) -}}
      {{- fail "Removed value: .Values.requireFreeWorkers was replaced by .Values.workersPerQuery in chart 3.0.0. Migrate `requireFreeWorkers.count: N` to `workersPerQuery.default: N`, adding `workersPerQuery.max: N` to keep the previous per-query cap. For `requireFreeWorkers.enabled: false`, set `workersPerQuery.default` explicitly when `scaling.enabled` is true. Then delete `requireFreeWorkers` from your values." -}}
    {{- end -}}
  {{- end -}}

  {{/*
  Workers the distributed e2e test may request, or empty when the deployment cannot
  reach the two workers it needs to observe fan-out. The test pins this count so the
  scheduler drives the pool to it; a ceiling of 0 below means unbounded.
  */}}
  {{- define "polars.tests.distributedWorkers" -}}
    {{- $required := 2 -}}
    {{- $ceiling := 0 -}}
    {{- if include "polars.isAutoscalingEnabled" . -}}
      {{- with include "polars.scaling.maxReplicas" . }}{{ $ceiling = . | int }}{{ end -}}
    {{- else -}}
      {{- $ceiling = .Values.worker.deployment.replicaCount | int -}}
    {{- end -}}
    {{- with include "polars.workersPerQuery.max" . -}}
      {{- if or (eq $ceiling 0) (lt (. | int) $ceiling) }}{{ $ceiling = . | int }}{{ end -}}
    {{- end -}}
    {{- if or (eq $ceiling 0) (ge $ceiling $required) }}{{ $required }}{{ end -}}
  {{- end -}}
