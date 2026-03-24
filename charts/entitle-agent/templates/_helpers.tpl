{{/*
Expand the name of the chart.
*/}}
{{- define "entitle-agent.name" -}}
{{- default "entitle-agent" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "entitle-agent.fullname" -}}
{{- printf "%s" "entitle-agent" | trunc 63}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "entitle-agent.chart" -}}
{{- printf "%s-%s" "entitle-agent" .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "entitle-agent.labels" -}}
helm.sh/chart: {{ include "entitle-agent.chart" . }}
{{ include "entitle-agent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "entitle-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "entitle-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account annotations
*/}}
{{- define "entitle-agent.serviceAccountName" -}}
{{- default "entitle-agent-sa" | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
Service account labels
*/}}
{{- define "entitle-agent.serviceAccountLabels" -}}
{{- if eq .Values.platform.mode "azure" -}}
azure.workload.identity/use: "true"
{{- end }}
{{- end }}


{{/*
Service Accounts annotations
*/}}
{{- define "entitle-agent.serviceAccountAnnotations" -}}
{{- if eq .Values.platform.mode "aws" -}}
eks.amazonaws.com/role-arn: {{ .Values.platform.aws.iamRole }}
{{- else if eq .Values.platform.mode "gcp" -}}
iam.gke.io/gcp-service-account: {{ printf "%s@%s.iam.gserviceaccount.com" .Values.platform.gke.serviceAccount .Values.platform.gke.projectId | quote}}
{{- else if eq .Values.platform.mode "azure" -}}
azure.workload.identity/client-id: {{ .Values.platform.azure.clientId }}
azure.workload.identity/tenant-id: {{ .Values.platform.azure.tenantId }}
{{- else -}}
{{- end }}
{{- end }}

{{/*
Image Tag
*/}}
{{- define "entitle-agent.imageTag" -}}
{{ .Values.agent.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/*
Fullname with image tag
*/}}
{{- define "entitle-agent.fullnameWithImageTag" -}}
{{- printf "%s_%s" (include "entitle-agent.fullname" .) (include "entitle-agent.imageTag" .) | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
Node selector
*/}}
{{- define "entitle-agent.nodeSelector" -}}
{{- if .Values.nodeSelector }}
{{- toYaml .Values.nodeSelector | nindent 8 }}
{{- end }}
{{- end }}
{{/*
*/}}

{{/* Datadog proxy helper functions */}}

{{/* Gets token from agent.token */}}
{{- define "entitle-agent.getToken" -}}
  {{- if and $.Values.agent $.Values.agent.token -}}
    {{- $.Values.agent.token -}}
  {{- end -}}
{{- end -}}

{{/* Extracts a field from the base64-encoded token JSON.
     Usage: include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "fieldName") */}}
{{- define "entitle-agent.extractTokenField" -}}
  {{- if .token -}}
    {{- $decoded := .token | b64dec -}}
    {{- if hasPrefix "{" $decoded -}}
      {{- $json := $decoded | fromJson -}}
      {{- if hasKey $json .field -}}
        {{- index $json .field -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Resolves datadogApiKey: --set datadog.datadog.apiKey takes priority, otherwise extract from token */}}
{{- define "entitle-agent.datadogApiKey" -}}
  {{- if and .Values.datadog.datadog.apiKey (ne .Values.datadog.datadog.apiKey "") -}}
    {{- .Values.datadog.datadog.apiKey -}}
  {{- else -}}
    {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "datadogApiKey") -}}
  {{- end -}}
{{- end -}}

{{/* Resolves imageCredentials: --set imageCredentials takes priority, otherwise extract from token */}}
{{- define "entitle-agent.imageCredentials" -}}
  {{- if and .Values.imageCredentials (ne .Values.imageCredentials "MISSING_CUSTOMER_DATA") -}}
    {{- .Values.imageCredentials -}}
  {{- else -}}
    {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "imageCredentials") -}}
  {{- end -}}
{{- end -}}

{{/* Extracts "routing" field from token */}}
{{- define "entitle-agent.extractedRouting" -}}
  {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "routing") -}}
{{- end -}}

{{/* Extracts "platform" field from token */}}
{{- define "entitle-agent.extractedPlatform" -}}
  {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "platform") -}}
{{- end -}}

{{/* Generates proxy URL from platform value
     Standard: http://agent.{platform}.entitle.io:8080
     Dev:      http://agent-{num}.dev.entitle.io:8080 (for dev-one, dev-two, dev-three)
*/}}
{{- define "entitle-agent.proxyUrl" -}}
  {{- $platform := include "entitle-agent.extractedPlatform" . | trim -}}
  {{- if $platform -}}
    {{- if hasPrefix "dev-" $platform -}}
      {{- $devNum := trimPrefix "dev-" $platform -}}
      {{- printf "http://agent-%s.dev.entitle.io:8080" $devNum -}}
    {{- else -}}
      {{- printf "http://agent.%s.entitle.io:8080" $platform -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Auto-update helper functions */}}

{{/* Extracts "autoUpdate" field from token */}}
{{- define "entitle-agent.extractedAutoUpdate" -}}
  {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "autoUpdate") -}}
{{- end -}}

{{/*
Validates agent_version + image.tag compatibility. Fails helm install on incompatible combos.
*/}}
{{- define "entitle-agent.validateAgentVersion" -}}
  {{- $imageTag := .Values.agent.image.tag | default "latest" -}}
  {{- $agentVersion := .Values.agent.agent_version | default "default" -}}
  {{- $isLatest := eq $imageTag "latest" -}}
  {{- $isKnownKeyword := or (eq $agentVersion "default") (eq $agentVersion "auto-update") (eq $agentVersion "latest-on-restart") -}}

  {{- if not $isLatest -}}
    {{- if or (eq $agentVersion "auto-update") (eq $agentVersion "latest-on-restart") -}}
      {{- fail (printf "You can't set agent_version='%s' with a manually set value for agent.image.tag. Please unset agent.image.tag." $agentVersion) -}}
    {{- end -}}
    {{- if not $isKnownKeyword -}}
      {{- fail "You can't set both agent_version and agent.image.tag, please unset agent.image.tag." -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Resolves the effective image tag based on agent_version and image.tag.
  - Custom image.tag (non-latest) + default => custom tag (legacy)
  - latest + keyword (default/auto-update/latest-on-restart) => latest
  - latest + hardcoded version (e.g. 2.7.4) => that version
*/}}
{{- define "entitle-agent.resolvedImageTag" -}}
  {{- $imageTag := .Values.agent.image.tag | default "latest" -}}
  {{- $agentVersion := .Values.agent.agent_version | default "default" -}}
  {{- $isLatest := eq $imageTag "latest" -}}
  {{- $isKnownKeyword := or (eq $agentVersion "default") (eq $agentVersion "auto-update") (eq $agentVersion "latest-on-restart") -}}

  {{- if not $isLatest -}}
    {{- $imageTag -}}
  {{- else if $isKnownKeyword -}}
    {{- "latest" -}}
  {{- else -}}
    {{- $agentVersion -}}
  {{- end -}}
{{- end -}}

{{/*
Resolves restart policy: "always" or "never".
  - Custom image.tag (non-latest) => never
  - default + autoUpdate missing/v0 => never
  - default + autoUpdate v1 => always
  - latest-on-restart => never
  - auto-update => always
  - hardcoded version => never
*/}}
{{- define "entitle-agent.resolvedRestartPolicy" -}}
  {{- $imageTag := .Values.agent.image.tag | default "latest" -}}
  {{- $agentVersion := .Values.agent.agent_version | default "default" -}}
  {{- $isLatest := eq $imageTag "latest" -}}
  {{- $autoUpdate := include "entitle-agent.extractedAutoUpdate" . -}}

  {{- if not $isLatest -}}
    {{- "never" -}}
  {{- else if eq $agentVersion "auto-update" -}}
    {{- "always" -}}
  {{- else if eq $agentVersion "latest-on-restart" -}}
    {{- "never" -}}
  {{- else if eq $agentVersion "default" -}}
    {{- if eq $autoUpdate "v1" -}}
      {{- "always" -}}
    {{- else -}}
      {{- "never" -}}
    {{- end -}}
  {{- else -}}
    {{- "never" -}}
  {{- end -}}
{{- end -}}

