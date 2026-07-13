{{/*
=============================================================================
Default image repository constants for proxy-rewrite detection.
IMPORTANT: These must match the defaults in values.yaml at:
  - agent.image.repository
  - datadog.image.repository
=============================================================================
*/}}

{{- define "entitle-agent.defaultAgentRepository" -}}
ghcr.io/anycred/entitle-agent
{{- end -}}

{{- define "entitle-agent.defaultDatadogRepository" -}}
gcr.io/datadoghq/agent
{{- end -}}

{{/*
=============================================================================
Safe accessors for fields introduced in v2.0.0 — prevents nil pointer errors
during --reuse-values upgrades from v1.x (where these fields don't exist).
=============================================================================
*/}}

{{/*
Safe accessor for agent.secretRef.name — returns empty string if not set.
Use this instead of direct .Values.agent.secretRef.name access.
*/}}
{{- define "entitle-agent.secretRefNameValue" -}}
{{- if hasKey .Values.agent "secretRef" -}}
{{- .Values.agent.secretRef.name | default "" -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

{{/*
Safe accessor for imagePullSecret.name — returns empty string if not set.
Use this instead of direct .Values.imagePullSecret.name access.
*/}}
{{- define "entitle-agent.imagePullSecretNameValue" -}}
{{- if hasKey .Values "imagePullSecret" -}}
{{- .Values.imagePullSecret.name | default "" -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

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
{{- else if eq .Values.platform.mode "gcp" }}
{{- $gcpSA := .Values.platform.gcp.serviceAccount | default .Values.platform.gke.serviceAccount }}
{{- $gcpProject := .Values.platform.gcp.projectId | default .Values.platform.gke.projectId }}
iam.gke.io/gcp-service-account: {{ printf "%s@%s.iam.gserviceaccount.com" $gcpSA $gcpProject | quote}}
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

{{/* Gets token from agent.token (returns empty if MISSING_CUSTOMER_DATA placeholder) */}}
{{- define "entitle-agent.getToken" -}}
  {{- if and $.Values.agent $.Values.agent.token (ne $.Values.agent.token "MISSING_CUSTOMER_DATA") -}}
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

{{/* Resolves datadogApiKey: explicit value > extract from agent.token */}}
{{- define "entitle-agent.datadogApiKey" -}}
  {{- if and .Values.datadog.datadog.apiKey (ne .Values.datadog.datadog.apiKey "") -}}
    {{- .Values.datadog.datadog.apiKey -}}
  {{- else -}}
    {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "datadogApiKey") -}}
  {{- end -}}
{{- end -}}

{{/* Resolves imageCredentials: explicit value > extract from agent.token */}}
{{- define "entitle-agent.imageCredentials" -}}
  {{- if and .Values.imageCredentials (ne .Values.imageCredentials "") (ne .Values.imageCredentials "MISSING_CUSTOMER_DATA") -}}
    {{- .Values.imageCredentials -}}
  {{- else -}}
    {{- include "entitle-agent.extractTokenField" (dict "token" (include "entitle-agent.getToken" .) "field" "imageCredentials") -}}
  {{- end -}}
{{- end -}}

{{/*
Validates that the credentials needed for a working deployment can be resolved at
render time, and fails helm install/upgrade with an actionable message if not.

Background: since chart v2.0.0 imageCredentials/datadogApiKey are auto-extracted from
the agent.token blob. Customers on an older token that lacks these fields who upgrade
without passing them explicitly used to get a silently-broken deploy (agent pods in
ImagePullBackOff, Datadog pods in CrashLoopBackOff). This validator surfaces the problem
up front instead.

Only the render-time path is validated. When agent.secretRef.name is set without a token,
the token lives in a pre-existing Secret that is not readable at render time — the
hook-extract-job.yaml Job resolves and patches the credentials at runtime, so we skip.
*/}}
{{- define "entitle-agent.validateRequiredCredentials" -}}
  {{- $hasToken := and .Values.agent.token (ne .Values.agent.token "MISSING_CUSTOMER_DATA") -}}
  {{- $secretRefName := include "entitle-agent.secretRefNameValue" . -}}
  {{- $imagePullSecretName := include "entitle-agent.imagePullSecretNameValue" . -}}
  {{- $isRuntimeSecretRef := and $secretRefName (not $hasToken) -}}
  {{- if not $isRuntimeSecretRef -}}
    {{- if not $imagePullSecretName -}}
      {{- if not (include "entitle-agent.imageCredentials" . | trim) -}}
        {{- fail (include "entitle-agent.missingImageCredentialsMessage" .) -}}
      {{- end -}}
    {{- end -}}
    {{- if .Values.datadog.enabled -}}
      {{- if not (include "entitle-agent.datadogApiKey" . | trim) -}}
        {{- fail (include "entitle-agent.missingDatadogApiKeyMessage" .) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Failure message for an unresolvable imageCredentials. */}}
{{- define "entitle-agent.missingImageCredentialsMessage" -}}
entitle-agent: imageCredentials is missing.
It could not be resolved (from the agent.token or an explicit --set value): your token blob has no 'imageCredentials' field — likely an older token — and no override was provided. Without it the agent image cannot be pulled (ImagePullBackOff).
Provide it in one of these ways:
  1. Issue a new token from Entitle (Org Settings), then pass it: --set agent.token=<TOKEN>
  2. Pass the credentials explicitly: --set imageCredentials=<base64-dockerconfigjson>
  3. Reference a pre-existing image pull Secret: --set imagePullSecret.name=<secret-name>
Upgrading an existing release? Add --reuse-values to keep the values from your previous install.
Docs: https://docs.beyondtrust.com/entitle/docs/entitle-agent
{{- end -}}

{{/* Failure message for an unresolvable datadogApiKey (only when datadog.enabled). */}}
{{- define "entitle-agent.missingDatadogApiKeyMessage" -}}
entitle-agent: datadogApiKey is missing (datadog.enabled=true).
It could not be resolved (from the agent.token or an explicit --set value): your token blob has no 'datadogApiKey' field — likely an older token — and no override was provided. Without it the Datadog pods crash (CrashLoopBackOff).
Provide it in one of these ways:
  1. Issue a new token from Entitle (Org Settings), then pass it: --set agent.token=<TOKEN>
  2. Pass the key explicitly: --set datadog.datadog.apiKey=<datadog-api-key>
  3. Disable Datadog if you don't use it: --set datadog.enabled=false
Upgrading an existing release? Add --reuse-values to keep the values from your previous install.
Docs: https://docs.beyondtrust.com/entitle/docs/entitle-agent
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

{{/* Full Datadog logs sidecar image reference including tag.
     Selected by the token's "routing" field:
       v0 / field absent  -> `datadog.image.repository`:`datadog.image.tag` as-is
       v1 (or higher)     -> pull through the proxy ONLY if using the default repository.
                             Rewrite to `<proxyHost>/monitoring-agent/<basename>:<tag>` where
                             basename is the last "/"-separated segment of the
                             configured repository. Uses the same proxy host as
                             the agent image (agent.{platform}.entitle.io, from
                             entitle-agent.proxyUrl); the "monitoring-agent"
                             alias namespace is mapped back to the real upstream
                             by the proxy.
                             If a custom (non-default) repository is explicitly configured,
                             use it as-is to allow direct pulls from private mirrors. */}}
{{- define "entitle-agent.datadogImage" -}}
  {{- $repository := .Values.datadog.image.repository -}}
  {{- $tag := .Values.datadog.image.tag | default "latest" -}}
  {{- $routing := include "entitle-agent.extractedRouting" . | trim -}}
  {{- $proxyUrl := include "entitle-agent.proxyUrl" . -}}
  {{- $defaultDatadogRepo := include "entitle-agent.defaultDatadogRepository" . -}}
  {{- $isDefault := eq $repository $defaultDatadogRepo -}}
  {{- if and $routing (ne $routing "v0") $proxyUrl $isDefault -}}
    {{- $host := $proxyUrl | trimPrefix "http://" | trimSuffix ":8080" -}}
    {{- $basename := regexReplaceAll "^.*/" $repository "" -}}
    {{- printf "%s/monitoring-agent/%s:%s" $host $basename $tag -}}
  {{- else -}}
    {{- printf "%s:%s" $repository $tag -}}
  {{- end -}}
{{- end -}}

{{/* Agent image repository, selected by the token's "routing" field (mirrors
     entitle-agent.datadogRegistry):
       v0 / field absent  -> pull direct from the configured registry (agent.image.repository)
       v1 (or higher)     -> pull through the proxy ONLY if using the default repository.
                             Swap the registry host for the proxy host
                             (agent.{platform}.entitle.io), keeping the repo path. The
                             proxy's default/catch-all route forwards it to the real upstream
                             (ghcr.io), so the image ref never embeds the upstream host.
                             If a custom (non-default) repository is explicitly configured,
                             use it as-is to allow direct pulls from private mirrors. */}}
{{- define "entitle-agent.agentImageRepository" -}}
  {{- $routing := include "entitle-agent.extractedRouting" . | trim -}}
  {{- $proxyUrl := include "entitle-agent.proxyUrl" . -}}
  {{- $repository := .Values.agent.image.repository -}}
  {{- $defaultAgentRepo := include "entitle-agent.defaultAgentRepository" . -}}
  {{- $isDefault := eq $repository $defaultAgentRepo -}}
  {{- if and $routing (ne $routing "v0") $proxyUrl $isDefault -}}
    {{- $host := $proxyUrl | trimPrefix "http://" | trimSuffix ":8080" -}}
    {{- $path := regexReplaceAll "^[^/]+/" $repository "" -}}
    {{- printf "%s/%s" $host $path -}}
  {{- else -}}
    {{- $repository -}}
  {{- end -}}
{{- end -}}

{{/* dockerconfigjson for the agent image pull secret. The agent image is private
     (ghcr), so containerd needs registry credentials keyed to the host in the image
     ref. When pulling through the proxy (routing v1+) that host is the proxy host, so
     re-key the auths entries from the upstream registry host to the proxy host (the
     username/password are unchanged — the proxy forwards the basic-auth /token call to
     the real upstream). Only rewrite if the agent repository is using the default.
     If agent is custom, pass imageCredentials through unchanged to allow direct pulls
     from private mirrors. */}}
{{- define "entitle-agent.dockerConfigJson" -}}
  {{- $imageCreds := include "entitle-agent.imageCredentials" . -}}
  {{- $routing := include "entitle-agent.extractedRouting" . | trim -}}
  {{- $proxyUrl := include "entitle-agent.proxyUrl" . -}}
  {{- $defaultAgentRepo := include "entitle-agent.defaultAgentRepository" . -}}
  {{- $agentIsDefault := eq .Values.agent.image.repository $defaultAgentRepo -}}
  {{- if and $imageCreds $routing (ne $routing "v0") $proxyUrl $agentIsDefault -}}
    {{- $host := $proxyUrl | trimPrefix "http://" | trimSuffix ":8080" -}}
    {{- $decoded := $imageCreds | b64dec | fromJson -}}
    {{- $newAuths := dict -}}
    {{- range $k, $v := $decoded.auths -}}
      {{- $_ := set $newAuths $host $v -}}
    {{- end -}}
    {{- dict "auths" $newAuths | toJson | b64enc -}}
  {{- else -}}
    {{- $imageCreds -}}
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
{{- $secretRefName := include "entitle-agent.secretRefNameValue" . -}}
{{- if $secretRefName -}}
{{- $secretRefName -}}
{{- else -}}
{{- include "entitle-agent.fullname" . }}-secret
{{- end -}}
{{- end }}

{{/*
Agent secret key — the key inside the Secret that holds the agent configuration.
Defaults to ENTITLE_JSON_CONFIGURATION but can be overridden via agent.secretRef.key.
*/}}
{{- define "entitle-agent.agentSecretKey" -}}
{{- if hasKey .Values.agent "secretRef" -}}
{{- .Values.agent.secretRef.key | default "ENTITLE_JSON_CONFIGURATION" -}}
{{- else -}}
{{- "ENTITLE_JSON_CONFIGURATION" -}}
{{- end -}}
{{- end }}

{{/*
Image pull secret name — resolves to the Secret for pulling the agent image.
Returns imagePullSecret.name if set, otherwise the chart-managed docker-login secret.
*/}}
{{- define "entitle-agent.imagePullSecretName" -}}
{{- $imagePullSecretName := include "entitle-agent.imagePullSecretNameValue" . -}}
{{- if $imagePullSecretName -}}
{{- $imagePullSecretName -}}
{{- else -}}
{{- include "entitle-agent.fullname" . }}-docker-login
{{- end -}}
{{- end }}

{{/*
Agent container env block — shared between the main agent container and the
healthcheck init container so validators run with identical configuration.
*/}}
{{- define "entitle-agent.agentEnv" -}}
- name: ENTITLE_ROUTING_VERSION
  value: {{ include "entitle-agent.extractedRouting" . | quote }}
- name: ENTITLE_PLATFORM
  value: {{ include "entitle-agent.extractedPlatform" . | quote }}
- name: ENTITLE_PROXY_URL
  value: {{ include "entitle-agent.proxyUrl" . | quote }}
- name: ENTITLE_MAX_ROUTING_VERSION
  value: "v1"
- name: HELM_AGENT_VERSION
  value: {{ .Values.agent.agent_version | default "default" | quote }}
- name: HELM_AGENT_IMAGE_TAG
  value: {{ include "entitle-agent.resolvedImageTag" . | quote }}
- name: HELM_RESTART_POLICY
  value: {{ include "entitle-agent.resolvedRestartPolicy" . | quote }}
{{- if eq .Values.kmsType "hashicorp_vault" }}
- name: HASHICORP_VAULT_CONNECTION_STRING
  valueFrom:
    secretKeyRef:
      name: {{ include "entitle-agent.fullname" . }}-hashicorp-vault-secret
      key: HASHICORP_VAULT_CONNECTION_STRING
{{- end }}
- name: ENTITLE_KMS_TYPE
  value: {{ .Values.kmsType }}
{{- if .Values.agent.kafka.bootstrapServers }}
- name: ENTITLE_KAFKA_BOOTSTRAP_SERVERS
  value: {{ .Values.agent.kafka.bootstrapServers }}
{{- end }}
- name: ENTITLE_JSON_CONFIGURATION
  valueFrom:
    secretKeyRef:
      name: {{ include "entitle-agent.agentSecretName" . }}
      key: {{ include "entitle-agent.agentSecretKey" . }}
      optional: false
{{- if eq .Values.platform.mode "azure" }}
- name: AZURE_KEY_VAULT_NAME
  value: {{ .Values.platform.azure.keyVaultName }}
{{- end }}
{{- if not .Values.datadog.enabled }}
- name: ENTITLE_LOG_TO_FILE
  value: "true"
{{- end }}
{{- end }}

{{/* ============================================================
     Auto-update helper functions
     ============================================================ */}}

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
