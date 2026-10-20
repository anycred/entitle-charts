{{/* ============================================================
     Helm event hook Jobs (hook-helm-event-job.yaml)
     ============================================================ */}}

{{/* "true" unless helmEvents.enabled is false. A release upgraded with --reuse-values from a
     chart without helmEvents keeps the default (on). */}}
{{- define "entitle-agent.helmEventsEnabled" -}}
{{- if and (hasKey .Values "helmEvents") (hasKey .Values.helmEvents "enabled") -}}
{{- if .Values.helmEvents.enabled -}}true{{- end -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/* POSTs $HELM_EVENT + sent_at (UTC) to the agent gateway with the token's clientSecret.
     Routing v2+ only; always exits 0; never prints the secret. */}}
{{- define "entitle-agent.helmEventScript" -}}
set +e
{{ include "entitle-agent.runtimeJsonHelpers" . }}
FULL_TOKEN=$(jget BASE64_CONFIGURATION 2>/dev/null < "/secret/{{ include "entitle-agent.agentSecretKey" . }}" | base64 -d 2>/dev/null)
ROUTING=$(printf '%s' "$FULL_TOKEN" | jget routing 2>/dev/null)
PLATFORM=$(printf '%s' "$FULL_TOKEN" | jget platform 2>/dev/null)
CLIENT_SECRET=$(printf '%s' "$FULL_TOKEN" | jget clientSecret 2>/dev/null)
{{ include "entitle-agent.runtimeRoutingVersion" . }} {{- /* sets ROUTING_VER from ROUTING */}}
SKIP=""
if [ -z "$FULL_TOKEN" ]; then
  SKIP="could not read the token from Secret {{ include "entitle-agent.agentSecretName" . }}, key {{ include "entitle-agent.agentSecretKey" . }}"
elif [ "$ROUTING_VER" -lt 2 ]; then
  SKIP="the token's routing is '${ROUTING:-none}', and helm events need routing v2 or later"
elif [ -z "$PLATFORM" ]; then
  SKIP="the routing ${ROUTING} token has no platform, so the agent gateway is unknown"
elif [ -z "$CLIENT_SECRET" ]; then
  SKIP="the routing ${ROUTING} token has no clientSecret to authenticate to the agent gateway"
fi
if [ -n "$SKIP" ]; then
  echo "Helm event not sent: $SKIP."
  exit 0
fi
{{ include "entitle-agent.runtimeProxyHost" . }}
export PROXY_HOST CLIENT_SECRET
python3 - <<'PY'
import base64, datetime, json, os, ssl, time, urllib.error, urllib.request
event = dict(json.loads(os.environ['HELM_EVENT']), sent_at=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'))
credential = base64.b64encode(('proxy-auth:' + os.environ['CLIENT_SECRET']).encode()).decode()
request = urllib.request.Request('https://' + os.environ['PROXY_HOST'] + '/agents/helm-event', data=json.dumps(event).encode(),
                                 headers={'Content-Type': 'application/json', 'Authorization': 'Basic ' + credential})
context = ssl.create_default_context(cafile=os.environ.get('ENTITLE_CUSTOM_CA_CERT_PATH') or None)
# 3 attempts, 2s then 4s apart: at most ~40s, well inside activeDeadlineSeconds. Only network
# errors, 429 and 5xx are retried; any other HTTP error will not change on a retry.
for attempt in range(1, 4):
    try:
        print('Helm event sent: HTTP %d' % urllib.request.urlopen(request, timeout=10, context=context).status)
        break
    except Exception as e:
        code = getattr(e, 'code', '')
        print('Helm event not sent (attempt %d/3): %s %s' % (attempt, type(e).__name__, code))
        if attempt == 3 or (isinstance(e, urllib.error.HTTPError) and code != 429 and code < 500):
            break
        time.sleep(2 * attempt)
PY
exit 0
{{- end -}}
