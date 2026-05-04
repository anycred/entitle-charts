{{/*
Expand the name of the chart.
*/}}
{{- define "entitle-agent.name" -}}
{{- default "entitle-agent" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Defaults to "entitle-agent" (hardcoded) for backward compatibility with existing
deployments. Use fullnameOverride to change resource names if needed.
*/}}
{{- define "entitle-agent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- default "entitle-agent" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "entitle-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource created by the chart.
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
Selector labels — used in spec.selector.matchLabels and pod template labels.
These are immutable after initial deploy (changing them breaks rolling updates).
*/}}
{{- define "entitle-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "entitle-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name — returns the configured SA name or the chart fullname.
*/}}
{{- define "entitle-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s-sa" (include "entitle-agent.fullname" .)) .Values.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Service account labels — adds Azure workload identity label when platform is azure.
*/}}
{{- define "entitle-agent.serviceAccountLabels" -}}
{{- if eq .Values.platform.mode "azure" -}}
azure.workload.identity/use: "true"
{{- end }}
{{- end }}

{{/*
Service account annotations — cloud-specific IAM annotations.
Configures IRSA (AWS), Workload Identity (GCP), or Workload Identity (Azure)
based on platform.mode. Merges with user-provided serviceAccount.annotations.
*/}}
{{- define "entitle-agent.serviceAccountAnnotations" -}}
{{- with .Values.serviceAccount.annotations }}
{{- toYaml . }}
{{- end }}
{{- if eq .Values.platform.mode "aws" }}
eks.amazonaws.com/role-arn: {{ .Values.platform.aws.iamRole }}
{{- else if eq .Values.platform.mode "gcp" }}
iam.gke.io/gcp-service-account: {{ printf "%s@%s.iam.gserviceaccount.com" .Values.platform.gcp.serviceAccount .Values.platform.gcp.projectId | quote}}
{{- else if eq .Values.platform.mode "azure" }}
azure.workload.identity/client-id: {{ .Values.platform.azure.clientId }}
azure.workload.identity/tenant-id: {{ .Values.platform.azure.tenantId }}
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

{{/* ============================================================
     Datadog proxy helper functions
     ============================================================ */}}

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
  {{- if and .Values.imageCredentials (ne .Values.imageCredentials "") -}}
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

{{/* ============================================================
     Secret reference helpers
     ============================================================ */}}

{{/*
Agent secret name — resolves to the Secret containing the agent token.
Returns agent.secretRef.name if set (pre-existing Secret managed outside Helm),
otherwise falls back to the chart-managed secret.
*/}}
{{- define "entitle-agent.agentSecretName" -}}
{{- if .Values.agent.secretRef.name -}}
{{- .Values.agent.secretRef.name -}}
{{- else -}}
{{- include "entitle-agent.fullname" . }}-secret
{{- end -}}
{{- end }}

{{/*
Agent secret key — the key inside the Secret that holds the agent configuration.
Defaults to ENTITLE_JSON_CONFIGURATION but can be overridden via agent.secretRef.key.
*/}}
{{- define "entitle-agent.agentSecretKey" -}}
{{- default "ENTITLE_JSON_CONFIGURATION" .Values.agent.secretRef.key -}}
{{- end }}

{{/*
Image pull secret name — resolves to the Secret for pulling the agent image.
Returns imagePullSecret.name if set, otherwise the chart-managed docker-login secret.
*/}}
{{- define "entitle-agent.imagePullSecretName" -}}
{{- if .Values.imagePullSecret.name -}}
{{- .Values.imagePullSecret.name -}}
{{- else -}}
{{- include "entitle-agent.fullname" . }}-docker-login
{{- end -}}
{{- end }}
