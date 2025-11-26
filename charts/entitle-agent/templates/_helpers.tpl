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
*/}}}}


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
{{
/* Fullname with image tag
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

{{/*
#################################################################
CUSTOM LOGIC FOR JFROG MIGRATION
#################################################################
*/}}

{{/*
Internal Helper: Try to extract imageCredentials from the Base64 encoded Token.
Returns the Base64 credential string if found, otherwise empty.
*/}}
{{- define "entitle-agent.extractedImageCredentials" -}}
{{- if .Values.agent.token -}}
  {{- $decoded := .Values.agent.token | b64dec -}}
  {{- /* formatting check: ensure it looks like JSON to avoid parsing errors */ -}}
  {{- if hasPrefix "{" $decoded -}}
    {{- $json := $decoded | fromJson -}}
    {{- if hasKey $json "imageCredentials" -}}
      {{- $json.imageCredentials -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Logic: Determine the Container Registry URL.
1. If the Token contains "imageCredentials" -> Force JFrog URL.
2. Else -> Use the value from values.yaml (Default: ghcr.io).
*/}}
{{- define "entitle-agent.repository" -}}
{{- $newCreds := include "entitle-agent.extractedImageCredentials" . -}}
{{- if $newCreds -}}
beyondtrust-eng-docker-prod-local.jfrog.io/beyondtrust/entitle/entitle-agent
{{- else -}}
{{- .Values.agent.image.repository -}}
{{- end -}}
{{- end -}}

{{/*
Logic: Determine the Docker Credentials to use.
1. If the Token contains "imageCredentials" -> Use them.
2. Else -> Use the value from values.yaml.
*/}}
{{- define "entitle-agent.finalImageCredentials" -}}
{{- $newCreds := include "entitle-agent.extractedImageCredentials" . -}}
{{- if $newCreds -}}
  {{- $newCreds -}}
{{- else -}}
  {{- .Values.imageCredentials -}}
{{- end -}}
{{- end -}}
