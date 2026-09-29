# Image for the entitle-agent chart's agent.secretRef hook Jobs
# (templates/hook-extract-job.yaml, templates/hook-patch-image-job.yaml).
# The hook scripts need bash, jq, kubectl and GNU base64 (-w0, from coreutils).
# Published public so it can be pulled before the Jobs have created the pull secret.
# Tag is taken from hook.image.tag in charts/entitle-agent/values.yaml — bump it on any change here.
# Pinned by digest for reproducible builds; Dependabot bumps tag + digest.
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.37.1

RUN apk add --no-cache bash jq coreutils \
 && apk add --no-cache --virtual .fetch curl \
 && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/kubectl \
 && apk del .fetch

USER 1001
