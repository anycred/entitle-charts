Entitle Agent
===========

A Helm Chart for Entitle's Agent.

## What's New in v2.0.0

- **Simplified install:** Just pass `agent.token` — the chart auto-extracts `imageCredentials` from the token blob. No need to decode and pass it separately.
- **Pre-existing Secret support:** New `agent.secretRef` lets you reference a pre-existing Kubernetes Secret instead of passing credentials at install time. A pre-install hook automatically extracts image pull credentials and Datadog API key from the token — single-value install.
- **Sane defaults:** `kmsType` defaults to `kubernetes_secret_manager`, `platform.mode` to `native`.
- **GCP field rename:** `platform.gke` renamed to `platform.gcp` for consistency.
- **Standard Helm patterns:** `nameOverride`, `fullnameOverride`, `serviceAccount` config, `podLabels`.
- **CI/CD:** Integration tests for all install scenarios, automated chart version bump on release.

### Upgrade Notes

If you're upgrading from v1.x:
- Existing `helm install` commands with explicit `--set agent.token=...` and `--set imageCredentials=...` continue to work unchanged.
- `imageCredentials` is now **optional** — it's auto-extracted from the token blob. You can remove it from your install commands.
- **GCP users:** `platform.gke.serviceAccount` and `platform.gke.projectId` are now `platform.gcp.serviceAccount` and `platform.gcp.projectId`.

## Installation Scenarios

The chart supports four installation scenarios. **The minimum required is 1 value.**

### Scenario 1 — Simple Install (Recommended)

Just pass the agent token blob. The chart auto-extracts `imageCredentials` and `datadogApiKey` from it.

```bash
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set agent.token="${TOKEN}" \
  --set kmsType="kubernetes_secret_manager" \
  -n entitle --create-namespace
```

### Scenario 2 — Pre-existing Secret (Single Value)

Reference a pre-existing Kubernetes Secret. A pre-install hook automatically extracts `imageCredentials` and `datadogApiKey` from the token inside the Secret — no additional configuration needed.

**Step 1 — Create the Secret:**

```bash
kubectl create secret generic entitle-agent-token \
  --from-literal=ENTITLE_JSON_CONFIGURATION='{"BASE64_CONFIGURATION":"<your-token>"}' \
  -n entitle
```

Or as YAML:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: entitle-agent-token
  namespace: entitle
stringData:
  ENTITLE_JSON_CONFIGURATION: '{"BASE64_CONFIGURATION":"<your-token>"}'
```

This works with any secret management tool — External Secrets Operator, Sealed Secrets, HashiCorp Vault, or plain `kubectl`.

**Step 2 — Install the chart:**

```bash
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set agent.secretRef.name="entitle-agent-token" \
  --set kmsType="kubernetes_secret_manager" \
  -n entitle --create-namespace
```

### Scenario 3 — Pre-existing Secret + Own Registry

If you manage your own image pull secret separately:

```bash
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set agent.secretRef.name="entitle-agent-token" \
  --set imagePullSecret.name="my-registry-secret" \
  --set kmsType="kubernetes_secret_manager" \
  -n entitle --create-namespace
```

### Scenario 4 — Explicit Override (Backwards-Compatible)

If you have existing automation that passes credentials explicitly, this still works:

```bash
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set agent.token="${TOKEN}" \
  --set imageCredentials="${IMAGE_CREDENTIALS}" \
  --set kmsType="kubernetes_secret_manager" \
  -n entitle --create-namespace
```

## Pre-Install

```shell
helm repo add datadog https://helm.datadoghq.com
helm repo add entitle https://anycred.github.io/entitle-charts/
```

<details>
<summary> Kubernetes Secret Manager Installation (Default) </summary>

## Kubernetes Secret Manager Installation (Default)

### General Note
Kubernetes Secret Manager is the default secret manager even if your K8s cluster is hosted on GCP/AWS/Azure.

### [Chart Installation](https://helm.sh/docs/helm/helm_upgrade/)

Helm Chart installation:

- `agent.token` is given to you by Entitle (imageCredentials is auto-extracted from the token)
- Replace `<YOUR_ORG_NAME>` in `datadog.tags` to your company name
- You can replace namespace `entitle` with your own namespace, but it's highly discouraged

```shell
export TOKEN=<TOKEN_FROM_ENTITLE>
export ORG_NAME=<YOUR ORGANIZATION NAME>
export NAMESPACE=entitle

helm upgrade --install entitle-agent entitle/entitle-agent \
    --set kmsType="kubernetes_secret_manager" \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set agent.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
```

<br /><br />
You are ready to go!

</details>

<details>
<summary> GCP Secret Manager Installation </summary>

## GCP Secret Manager installation

### A. Workload Identity

**Notice:** If you installed our IaC then you may now skip to the [chart installation part](#gcp-chart-installation).

Follow the following GCP (GKE) guides:

- [Google Kubernetes Engine (GKE) > Documentation > Guides > About Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
- [Google Kubernetes Engine (GKE) > Documentation > Guides > Use Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

In the step "**Configure applications to use Workload Identity**", use the following roles for the gcp service account:

- `roles/secretmanager.admin`
- `roles/iam.securityAdmin`
- `roles/container.developer`
- `roles/iam.workloadIdentityUser`

### B. Update `kubeconfig`

* If you have installed Entitle's Terraform IaC:

  You can set the environment variables using terraform output file `terraform_output.json`:
    ```shell
    BASTION_HOSTNAME=$(jq -r '.bastion_hostname.value' terraform_output.json)
    PROJECT_ID=$(jq -r '.project_id.value' terraform_output.json)
    ZONE=$(jq -r '.zone.value' terraform_output.json)
    REGION=$(jq -r '.region.value' terraform_output.json)
    CLUSTER_NAME=$(jq -r '.cluster_name.value' terraform_output.json)
    ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME=$(jq -r '.entitle_agent_gke_service_account_name.value' terraform_output.json)
    TOKEN=$(jq -r '.token.value' terraform_output.json)
    COSTUMER_NAME=$(jq -r '.costumer_name.value' terraform_output.json)
    NAMESPACE=$(jq -r '.namespace.value' terraform_output.json)
    AUTOPILOT=$(jq -r '.autopilot.value' terraform_output.json)
    AGENT_MODE=$(jq -r '.agent_mode.value' terraform_output.json)
    ```

* ### Setting up IAP-tunnel:
    ```shell
    gcloud beta compute ssh "<BASTION_HOSTNAME>" --tunnel-through-iap --project "<PROJECT_ID>" --zone "<ZONE>" -- -4 -N -L 8888:127.0.0.1:8888 -o "ExitOnForwardFailure yes" -o "ServerAliveInterval 10" &
    ```

In the following: If AutoPilot is enabled, replace --zone with --region

* If your cluster isn't configured on kubeconfig yet:
    ```shell
    gcloud container clusters get-credentials "<CLUSTER_NAME>" --zone "<ZONE>" --project "<PROJECT_ID>" --internal-ip
    ```

* Otherwise, simply replace `<CLUSTER_NAME>` and `<ZONE>` and run the following command:
    ```shell
    gcloud container clusters get-credentials <CLUSTER_NAME> --zone <ZONE>
    ```

### C. [GCP Chart Installation](https://helm.sh/docs/helm/helm_upgrade/)

- `agent.token` is given to you by Entitle
- Replace `<YOUR_ORG_NAME>` in `datadog.tags` to your company name

- If you have installed Entitle's Terraform IaC, you need to set up proxy(after [Setting up IAP-tunnel](#setting-up-iap-tunnel)):

```shell
export HTTPS_PROXY=localhost:8888
```

- If you want to use hashicorp vault, set kmsType to `hashicorp_vault`

```shell
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set platform.mode="gcp" \
  --set kmsType="gcp_secret_manager" \
  --set platform.gcp.serviceAccount="<ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME>" \
  --set platform.gcp.projectId="<PROJECT_ID>" \
  --set agent.token="<TOKEN>" \
  --set datadog.datadog.tags={company:<YOUR_ORG_NAME>} \
  -n "<NAMESPACE>" --create-namespace
```

If you set up environment variables you can use:

```shell
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set platform.mode="gcp" \
  --set kmsType="gcp_secret_manager" \
  --set datadog.providers.gke.autopilot="${AUTOPILOT}" \
  --set platform.gcp.serviceAccount="${ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME}" \
  --set platform.gcp.projectId="${PROJECT_ID}" \
  --set agent.token="${TOKEN}" \
  --set datadog.datadog.tags={company:${ORGANIZATION_NAME}} \
  -n "${NAMESPACE}" --create-namespace
```

</details>

<details>
<summary> AWS Secret Manager Installation </summary>

## AWS Secret Manager installation

### First things first:

#### A. Declare Variables

1. Define your cluster's name:
   ```shell
    export CLUSTER_NAME=<your-cluster-name>
   ```

2. Update kubeconfig:
   ```shell
    aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-2   # (or any other region)
   ```

3. **Notice:** If you installed our IaC then you may skip to the [chart installation part](#chart-installation).

#### B. [Create OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

You can check if you already have the Identity Provider for your cluster using one of the following:

- Run the following command:
  ```shell
    aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text
  ```
- Alternatively, refer to [IAM Identity Providers](https://console.aws.amazon.com/iamv2/home#/identity_providers) page in AWS Console.

If you don't have an OIDC provider, create new one:

```shell
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve
```

#### C. [Create IAM Policy and Role](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)

##### Create policy

  ```shell
  ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  echo $ACCOUNT_ID

  cat > entitle-agent-policy.json <<ENDOF
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "VisualEditor0",
              "Effect": "Allow",
              "Action": [
                "secretsmanager:UpdateSecret",
                "secretsmanager:TagResource",
                "secretsmanager:PutSecretValue",
                "secretsmanager:ListSecretVersionIds",
                "secretsmanager:GetSecretValue",
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:DescribeSecret",
                "secretsmanager:DeleteSecret",
                "secretsmanager:CreateSecret"
              ],
              "Resource": "arn:aws:secretsmanager:*:${ACCOUNT_ID}:secret:Entitle/*"
          },
          {
              "Sid": "VisualEditor1",
              "Effect": "Allow",
              "Action": "secretsmanager:ListSecrets",
              "Resource" : "*"
          }
      ]
  }
  ENDOF

  aws iam create-policy --policy-name entitle-agent-policy --policy-document file://entitle-agent-policy.json
  ```

##### Create IAM role and attach policy

```shell
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo $ACCOUNT_ID
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
echo $OIDC_PROVIDER

cat > trust.json <<ENDOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:entitle:entitle-agent-sa"
        }
      }
    }
  ]
}
ENDOF

aws iam create-role --role-name entitle-agent-role --assume-role-policy-document file://trust.json --description "Entitle Agent's AWS Role"
aws iam attach-role-policy --role-name entitle-agent-role --policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/entitle-agent-policy
```

### [Chart Installation](https://helm.sh/docs/helm/helm_upgrade/)

Eventually, you can install our Helm chart:

- `agent.token` is given to you by Entitle
- Replace `platform.aws.iamRole` with Entitle's AWS IAM Role you've created
- Replace `<YOUR_ORG_NAME>` in `datadog.tags` to your company name
- You can replace namespace `entitle` with your own namespace, but it's highly discouraged
- If you want to use hashicorp vault, set kmsType to `hashicorp_vault`

```shell
export TOKEN=<TOKEN_FROM_ENTITLE>
export ORG_NAME=<YOUR ORGANIZATION NAME>
export NAMESPACE=entitle

helm upgrade --install entitle-agent entitle/entitle-agent \
    --set platform.mode="aws" \
    --set kmsType="aws_secret_manager" \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set platform.aws.iamRole="arn:aws:iam::${ACCOUNT_ID}:role/entitle-agent-role" \
    --set agent.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
```

<br /><br />
You are ready to go!

</details>

<details>
<summary> Azure Secret Manager Installation </summary>

## Azure Secret Manager installation

By the end of installation, you will have fully working Entitle Agent on your Azure Kubernetes cluster.
The installation will be based upon the follow reading materials:

### Reading Material

- [Azure Resource Manager overview](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/overview)
- [Workload Identity](https://learn.microsoft.com/en-us/azure/aks/concepts-identity)
- [Use a workload identity with an application on Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/learn/tutorial-kubernetes-workload-identity)
- [Modernize application authentication with workload identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-migrate-from-pod-identity)
- [Provide an identity to access the Azure Key Vault Provider for Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access)
- [Deploy and configure workload identity on an Azure Kubernetes Service (AKS) cluster](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)

### Prerequisites

- An Azure subscription
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Helm v3 installed](https://helm.sh/docs/intro/install/)
- [kubectl installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [kubelogin installed](https://learn.microsoft.com/en-us/azure/aks/managed-aad#prerequisites)
- AKS cluster
- Verify the Azure CLI version 2.40.0 or later. Run `az --version` to find the version, and run az upgrade to upgrade the version. If you need to install or upgrade, see
  Install [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli).

#### Setup Environment Variables

```shell
export CLUSTER_NAME=<YOUR_AKS_CLUSTER_NAME>
export RESOURCE_GROUP=<YOUR_AKS_RESOURCE_GROUP>
export SUBSCRIPTION_ID=<YOUR_AZURE_SUBSCRIPTION_ID>
export LOCATION=<YOUR_AKS_LOCATION>
export NAMESPACE="entitle"
export SERVICE_ACCOUNT_NAME="entitle-agent-sa"
export WORKLOAD_IDENTITY_NAME=<YOUR_WORKLOAD_IDENTITY_NAME>
export FEDERATED_IDENTITY_NAME=<YOUR_FEDERATED_IDENTITY_NAME>
export KEY_VAULT_NAME=<YOUR_KEY_VAULT_NAME>
export AAD_GROUP_OBJECT_ID=<YOUR_AAD_GROUP_OBJECT_ID>
```

The variables `CLUSTER_NAME`, `RESOURCE_GROUP`, `SUBSCRIPTION_ID`, `LOCATION` can be found on the AKS cluster overview page.
The other variables are up to you. (we highly recommend to not change the `NAMESPACE` and `SERVICE_ACCOUNT_NAME`)

If you don't have a managed identity created and assigned to your pod, perform the following steps to create and grant the necessary permissions to Key Vault.

1. Set account subscription
    ```shell
    az account set --subscription ${SUBSCRIPTION_ID}
    ```
2. Install `aks-preview` extension
    ```shell
    az extension add --name aks-preview
    az extension update --name aks-preview
    ```
3. Register EnablePodIdentityPreview feature
    ```shell
    az feature register --namespace Microsoft.ContainerService --name EnablePodIdentityPreview
    ```
   It takes a few minutes for the status to show Registered. Verify the registration status by using the command:
   ```shell
    watch -g -n 5 az feature show --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview"
    ```
   Then run:
   ```shell
    az provider register --namespace Microsoft.ContainerService
    ```
4. Enabled AAD/OIDC/WORKLOAD IDENTITY for the cluster

   Verify that all the below not False/Null
    ```shell
   echo "$(az aks show -n ${CLUSTER_NAME} -g ${RESOURCE_GROUP} --query "oidcIssuerProfile.issuerUrl" -otsv)"
   echo "$(az aks show -n ${CLUSTER_NAME} -g ${RESOURCE_GROUP} --query "securityProfile.workloadIdentity" -otsv)"
   echo "$(az aks show -n ${CLUSTER_NAME} -g ${RESOURCE_GROUP} --query "aadProfile" -otsv)"
   ```
   If any of the above is False/Null, run the following command (with the right flags) to enable AAD/OIDC/WORKLOAD IDENTITY for the cluster:
    ```shell
    az aks update --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME} --enable-aad --aad-admin-group-object-ids ${AAD_GROUP_OBJECT_ID}  --enable-workload-identity --enable-oidc-issuer
    ```
5. Use the `az identity create` command to create a managed identity.
    ```shell
    az identity create --name "${WORKLOAD_IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --location "${LOCATION}" --subscription "${SUBSCRIPTION_ID}"
    export USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${RESOURCE_GROUP}" --name "${WORKLOAD_IDENTITY_NAME}" --query 'clientId' -otsv)"
    export TENANT_ID=$(az aks show --name ${CLUSTER_NAME} --resource-group "${RESOURCE_GROUP}" --query aadProfile.tenantId -o tsv)
    ```
6. Grant the managed identity the permissions required to access the resources in Azure it requires.
    ```shell
   az keyvault set-policy -n ${KEY_VAULT_NAME} --secret-permissions get set list delete --spn $USER_ASSIGNED_CLIENT_ID
    ```
7. To get the OIDC Issuer URL and save it to an environmental variable, run the following command
    ```shell
    export AKS_OIDC_ISSUER="$(az aks show -n ${CLUSTER_NAME} -g ${RESOURCE_GROUP} --query "oidcIssuerProfile.issuerUrl" -otsv)"
    echo "AKS_OIDC_ISSUER: ${AKS_OIDC_ISSUER}"
    ```
8. Set credentials for kubectl to connect to your AKS cluster
    ```shell
    az aks get-credentials -n ${CLUSTER_NAME} -g "${RESOURCE_GROUP}" --admin
    ```
   (`--admin` is optional, if you have a user with sufficient permissions you can omit it)
9. Use the `az identity federated-credential create` command to create the federated identity credential between the managed identity, the service account issuer, and the subject.
    ```shell
    az identity federated-credential create --name ${FEDERATED_IDENTITY_NAME} --identity-name ${WORKLOAD_IDENTITY_NAME} --resource-group ${RESOURCE_GROUP} --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}
    ```

10. Login with kubelogin
    There are several ways login with kubelogin according to the [documentation](https://github.com/Azure/kubelogin)
    But we recommend to use the interactive login:
    ```shell
    export KUBECONFIG=<PATH_TO_KUBECONFIG>
    kubelogin convert-kubeconfig
    kubectl get no
    ```
    You will get the following message:
    `To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ARJFDH6FU to authenticate.`
    Follow the instructions and login with your Azure account. After that you should see the nodes of your cluster.

11. helm install
    ```shell
    export TOKEN=<TOKEN_FROM_ENTITLE>
    export ORG_NAME=<YOUR ORGANIZATION NAME>
    ```

- If you want to use hashicorp vault, set kmsType to `hashicorp_vault`
    ```shell
    helm upgrade --install entitle-agent entitle/entitle-agent \
    --set platform.mode="azure" \
    --set kmsType="azure_secret_manager" \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set datadog.datadog.kubelet.tlsVerify=false \
    --set datadog.datadog.kubelet.host.valueFrom.fieldRef.fieldPath="spec.nodeName" \
    --set datadog.datadog.kubelet.hostCAPath="/etc/kubernetes/certs/kubeletserver.crt" \
    --set platform.azure.clientId=${USER_ASSIGNED_CLIENT_ID} \
    --set platform.azure.tenantId=${TENANT_ID} \
    --set platform.azure.keyVaultName=${KEY_VAULT_NAME} \
    --set agent.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
    ```
</details>

## Configuration

The following table lists the configurable parameters of the Entitle-agent chart and their default values.

| Parameter                        | Description                                                                                                                                                      | Default                           | Required                          |
|----------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------|-----------------------------------|
| `nameOverride`                   | Override the chart name used in resource names                                                                                                                   | `""`                              | `false`                           |
| `fullnameOverride`               | Fully override the generated resource names                                                                                                                      | `""`                              | `false`                           |
| `imageCredentials`               | Base64-encoded dockerconfigjson. **Optional** — auto-extracted from `agent.token` if not set.                                                                    | `"MISSING_CUSTOMER_DATA"`         | `false`                           |
| `imagePullSecret.name`           | Name of existing `kubernetes.io/dockerconfigjson` Secret for image pull.                                                                                         | `""`                              | `false`                           |
| `serviceAccount.create`          | Whether to create a ServiceAccount                                                                                                                               | `true`                            | `false`                           |
| `serviceAccount.name`            | Override the ServiceAccount name                                                                                                                                 | `""`                              | `false`                           |
| `serviceAccount.annotations`     | Additional annotations for the ServiceAccount                                                                                                                    | `{}`                              | `false`                           |
| `kmsType`                        | KMS for agent to save secrets. Values: `kubernetes_secret_manager`, `aws_secret_manager`, `gcp_secret_manager`, `azure_secret_manager`, `hashicorp_vault`        | `"kubernetes_secret_manager"`     | `true`                            |
| `platform.mode`                  | Cloud platform. Values: `native`, `aws`, `gcp`, `azure`                                                                                                         | `"native"`                        | `true`                            |
| `platform.aws.iamRole`           | IAM role ARN for agent's IRSA service account annotation                                                                                                         | `""`                              | `true` if `platform.mode="aws"`   |
| `platform.gcp.serviceAccount`    | GKE service account for agent's Workload Identity annotation                                                                                                     | `""`                              | `true` if `platform.mode="gcp"`   |
| `platform.gcp.projectId`         | GCP project ID for agent's Workload Identity annotation                                                                                                          | `""`                              | `true` if `platform.mode="gcp"`   |
| `platform.azure.clientId`        | Azure AD application client ID for workload identity                                                                                                             | `""`                              | `true` if `platform.mode="azure"` |
| `platform.azure.tenantId`        | Azure AD tenant ID for workload identity                                                                                                                         | `""`                              | `true` if `platform.mode="azure"` |
| `platform.azure.keyVaultName`    | Azure Key Vault name for storing agent secrets                                                                                                                   | `""`                              | `true` if `platform.mode="azure"` |
| `podAnnotations`                 | Additional annotations for agent pods                                                                                                                            | `{}`                              | `false`                           |
| `podLabels`                      | Additional labels for agent pods                                                                                                                                 | `{}`                              | `false`                           |
| `nodeSelector`                   | Node selector for agent pods                                                                                                                                     | `{}`                              | `false`                           |
| `affinity`                       | Affinity rules for agent pods                                                                                                                                    | `{}`                              | `false`                           |
| `tolerations`                    | Tolerations for agent pods                                                                                                                                       | `[]`                              | `false`                           |
| `global.environment`             | Deployment environment label; used in Datadog tags                                                                                                               | `"onprem"`                        | `false`                           |
| `agent.token`                    | Base64-encoded agent token blob from Entitle. Leave empty if using `agent.secretRef`.                                                                            | `"MISSING_CUSTOMER_DATA"`         | `true` (or `agent.secretRef.name`)  |
| `agent.secretRef.name`           | Name of existing Secret with agent configuration. When set, `agent.token` is ignored.                                                                            | `""`                              | `false`                           |
| `agent.secretRef.key`            | Key within the Secret that holds the agent configuration JSON.                                                                                                   | `"ENTITLE_JSON_CONFIGURATION"`    | `false`                           |
| `agent.image.repository`         | Docker image repository                                                                                                                                          | `"ghcr.io/anycred/entitle-agent"` | `false`                           |
| `agent.image.tag`                | Tag for docker image of agent                                                                                                                                    | `"latest"`                        | `false`                           |
| `agent.replicas`                 | Number of agent pods                                                                                                                                             | `3`                               | `false`                           |
| `agent.resources.requests.cpu`   | CPU request for agent pod                                                                                                                                        | `"1000m"`                         | `false`                           |
| `agent.resources.requests.memory`| Memory request for agent pod                                                                                                                                     | `"1Gi"`                           | `false`                           |
| `agent.resources.limits.cpu`     | CPU limit for agent pod                                                                                                                                          | `"5000m"`                         | `false`                           |
| `agent.resources.limits.memory`  | Memory limit for agent pod                                                                                                                                       | `"3Gi"`                           | `false`                           |
| `datadog.enabled`                | Enable the Datadog Helm subchart                                                                                                                                 | `true`                            | `false`                           |
| `datadog.sidecarLogs`            | Enable Datadog sidecar for log shipping (when datadog.enabled=false)                                                                                             | `true`                            | `false`                           |
| `datadog.datadog.apiKey`         | Datadog API key                                                                                                                                                  | `""`                              | `false`                           |
| `datadog.datadog.tags`           | Datadog tags (https://docs.datadoghq.com/tagging/)                                                                                                               | `[]`                              | `false`                           |
| `datadog.providers.gke.autopilot`| Whether to enable GKE autopilot mode                                                                                                                             | `false`                           | `false`                           |
