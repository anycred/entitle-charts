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
Service account name
*/}}
{{- define "entitle-agent.serviceAccountName" -}}
{{- default "entitle-agent-sa" | trunc 63 | trimSuffix "-" }}
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
based on platform.mode.
*/}}
{{- define "entitle-agent.serviceAccountAnnotations" -}}
{{- if eq .Values.platform.mode "aws" -}}
eks.amazonaws.com/role-arn: {{ .Values.platform.aws.iamRole }}
{{- else if eq .Values.platform.mode "gcp" -}}
iam.gke.io/gcp-service-account: {{ printf "%s@%s.iam.gserviceaccount.com" .Values.platform.gcp.serviceAccount .Values.platform.gcp.projectId | quote}}
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
     Secret name helpers — support for existingSecret pattern
     (GitOps / External Secrets Operator workflows)
     ============================================================ */}}

{{/*
Agent secret name — resolves to the appropriate Secret for the agent token.
Returns agent.existingSecret if set (for GitOps/ESO workflows where secrets are
managed outside Helm), otherwise falls back to the chart-managed secret name.
Used by: deployment.yaml (ENTITLE_JSON_CONFIGURATION env var)
*/}}
{{- define "entitle-agent.agentSecretName" -}}
{{- if .Values.agent.existingSecret -}}
{{- .Values.agent.existingSecret -}}
{{- else -}}
{{- include "entitle-agent.fullname" . }}-secret
{{- end -}}
{{- end }}

{{/*
Image pull secret name — resolves to the appropriate imagePullSecret.
Returns imagePullSecret.existingSecret if set (for GitOps/ESO workflows),
otherwise falls back to the chart-managed docker-login secret name.
Used by: deployment.yaml (imagePullSecrets)
*/}}
{{- define "entitle-agent.imagePullSecretName" -}}
{{- if .Values.imagePullSecret.existingSecret -}}
{{- .Values.imagePullSecret.existingSecret -}}
{{- else -}}
{{- include "entitle-agent.fullname" . }}-docker-login
{{- end -}}
{{- end }}

