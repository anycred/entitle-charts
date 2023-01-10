Entitle Agent
===========

A Helm Chart for Entitle's Agent.

## Pre-Install

```shell
helm repo add datadog https://helm.datadoghq.com
helm repo add entitle https://anycred.github.io/entitle-charts/
```

<details>
<summary> GCP Installation </summary>

## GCP installation

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
    IMAGE_CREDENTIALS=$(jq -r '.image_credentials.value' terraform_output.json)
    DATADOG_API_KEY=$(jq -r '.datadog_api_key.value' terraform_output.json)
    BASTION_SETUP_COMMAND=$(jq -r '.bastion_setup_command.value' terraform_output.json)
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

- `imageCredentials` and `agent.kafka.token` are given to you by Entitle
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
  --set imageCredentials="<IMAGE_CREDENTIALS>" \
  --set datadog.datadog.apiKey="<DATADOG_API_KEY>" \
  --set platform.gke.serviceAccount="<ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME>" \
  --set platform.gke.projectId="<PROJECT_ID>" \
  --set agent.kafka.token="<TOKEN>" \
  --set datadog.datadog.tags={company:<YOUR_ORG_NAME>} \
  -n "<NAMESPACE>" --create-namespace
```

If you set up environment variables you can use:

```shell
helm upgrade --install entitle-agent entitle/entitle-agent \
  --set platform.mode="gcp" \
  --set kmsType="gcp_secret_manager" \
  --set imageCredentials="${IMAGE_CREDENTIALS}" \
  --set datadog.datadog.apiKey="${DATADOG_API_KEY}" \
  --set datadog.providers.gke.autopilot="${AUTOPILOT}" \
  --set platform.gke.serviceAccount="${ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME}" \
  --set platform.gke.projectId="${PROJECT_ID}" \
  --set agent.kafka.token="${TOKEN}" \
  --set datadog.datadog.tags={company:${ORGANIZATION_NAME}} \
  -n "${NAMESPACE}" --create-namespace
```

</details>

<details>
<summary> AWS Installation </summary>

## AWS installation

### First things first:

#### A. Declare Variables

1. Define bash variable for `CLUSTER_NAME`:
   `CLUSTER_NAME=<your-cluster-name>`
1. Define your cluser's name:
   ```shell
    export CLUSTER_NAME=<your-cluster-name>
   ```

2. Update kubeconfig:
   `aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-2 # Or any other region`
   ```shell
    aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-2   # (or any other region)
   ```

**Notice:** If you installed our IAC then you may now skip to the [chart installation part](#chart-installation)

3. **Notice:** If you installed our IaC then you may skip to the [chart installation part](#chart-installation).

### [Create OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

#### B. [Create OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

You can check if you already have the identity provider for your cluster using one of the following:
You can check if you already have the Identity Provider for your cluster using one of the following:

- Run this command:
  `aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text`
- Or [here](https://us-east-1.console.aws.amazon.com/iamv2/home?region=us-east-1#/identity_providers).
- Run the following command:
  ```shell
    aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text
  ```
- Alternatively, refer to [IAM Identity Providers](https://console.aws.amazon.com/iamv2/home#/identity_providers) page in AWS Console.

If you don't have an OIDC provider, please create new one:
`eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve`
If you don't have an OIDC provider, create new one:

```shell
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve
```

### [Create IAM Policy and Role](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)

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

- `imageCredentials` and `agent.kafka.token` are given to you by Entitle
- Replace `platform.aws.iamRole` with Entitle's AWS IAM Role you've created
- Replace `<YOUR_ORG_NAME>` in `datadog.tags` to your company name
- You can replace namespace `entitle` with your own namespace, but it's not recommended
- If you want to use hashicorp vault, set kmsType to `hashicorp_vault`

```shell
export IMAGE_CREDENTIALS=<IMAGE_CREDENTIALS_FROM_ENTITLE>
export DATADOG_API_KEY=<DATADOG_API_KEY_FROM_ENTITLE>
export TOKEN=<TOKEN_FROM_ENTITLE>
export ORG_NAME=<YOUR ORGANIZATION NAME>
export NAMESPACE=entitle

helm upgrade --install entitle-agent entitle/entitle-agent \
    --set platform.mode="aws" \
    --set kmsType="aws_secret_manager" \
    --set imageCredentials=${IMAGE_CREDENTIALS} \
    --set datadog.datadog.apiKey=${DATADOG_API_KEY} \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set platform.aws.iamRole="arn:aws:iam::${ACCOUNT_ID}:role/entitle-agent-role" \
    --set agent.kafka.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
```

For backward compatibility, the for 0.x version, use:

```shell
export IMAGE_CREDENTIALS=<IMAGE_CREDENTIALS_FROM_ENTITLE>
export DATADOG_API_KEY=<DATADOG_API_KEY_FROM_ENTITLE>
export TOKEN=<TOKEN_FROM_ENTITLE>
export ORG_NAME=<YOUR ORGANIZATION NAME>

helm upgrade --install entitle-agent entitle/entitle-agent \
    --set platform.mode="aws" \
    --set kmsType="aws_secret_manager" \
    --set imageCredentials=${IMAGE_CREDENTIALS} \
    --set datadog.datadog.apiKey=${DATADOG_API_KEY} \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set platform.aws.iamRole="arn:aws:iam::${ACCOUNT_ID}:role/entitle-agent-role" \
    --set agent.mode=websocket \
    --set agent.websocket.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
```

<br /><br />
You are ready to go!

</details>

<details>
<summary> Azure Installation </summary>

## Azure installation

By the end of installation, you will have fully working Entitle Agent on your Azure Kubernetes cluster.
The installation will be based upon the follow reading materials:

### Reading Material

- [Azure Resource Manager overview](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/overview)
- [Workload Identity](https://learn.microsoft.com/en-us/azure/aks/concepts-identity)
- [Use a workload identity with an application on Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/learn/tutorial-kubernetes-workload-identity)
- [Modernize application authentication with workload identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-migrate-from-pod-identity)
- [Provide an identity to access the Azure Key Vault Provider for Secrets Store CSI Driver
  ](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access)
- [Deploy and configure workload identity (preview) on an Azure Kubernetes Service (AKS) cluster] (https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)

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

The variables `CLUSTRER_NAME`, `RESOURCE_GROUP`, `SUBSCRIPTION_ID`, `LOCATION` can be found on the AKS cluster overview page.
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
   (The -g or --chgexit option causes the watch command to exit if there is a change in the output)
   You'll get this message: `Once the feature 'EnablePodIdentityPreview' is registered, invoking 'az provider register -n Microsoft.ContainerService' is required to get the change propagated`
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
8. Set credentials for kubctl to connect to your AKS cluster
    ```shell
    az aks get-credentials -n ${CLUSTER_NAME} -g "${RESOURCE_GROUP}" --admin
    ```
   (`--admin` is optional, if you have a user with sufficient permissions you can omit it)
9. Use the `az identity federated-credential create` command to create the federated identity credential between the managed identity, the service account issuer, and the subject.
    ```shell
    az identity federated-credential create --name ${FEDERATED_IDENTITY_NAME} --identity-name ${WORKLOAD_IDENTITY_NAME} --resource-group ${RESOURCE_GROUP} --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}
    ```

10. Login with kubelogin
    There are serveral ways login with kubelogin according to the [documentation](https://github.com/Azure/kubelogin)
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
    export IMAGE_CREDENTIALS=<IMAGE_CREDENTIALS_FROM_ENTITLE>
    export DATADOG_API_KEY=<DATADOG_API_KEY_FROM_ENTITLE>
    export TOKEN=<TOKEN_FROM_ENTITLE>
    export ORG_NAME=<YOUR ORGANIZATION NAME> 
    ```
    - IMAGE_CREDENTIALS: The credentials to pull the Entitle Agent image from the Entitle registry. (will be provided by Entitle)
    - DATADOG_API_KEY: The API key for Datadog. (will be provided by Entitle)
    - TOKEN: The token to authenticate with Entitle. (will be provided by Entitle)
    - ORG_NAME: The name of your organization

- If you want to use hashicorp vault, set kmsType to `hashicorp_vault`
    ```shell
    helm upgrade --install entitle-agent entitle/entitle-agent \
    --set platform.mode="azure" \
    --set kmsType="azure_secret_manager" \
    --set imageCredentials=${IMAGE_CREDENTIALS} \
    --set datadog.datadog.apiKey=${DATADOG_API_KEY} \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set datadog.datadog.kubelet.tlsVerify=false \
    --set datadog.datadog.kubelet.host.valueFrom.fieldRef.fieldPath="spec.nodeName" \
    --set datadog.datadog.kubelet.hostCAPath="/etc/kubernetes/certs/kubeletserver.crt" \
    --set platform.azure.clientId=${USER_ASSIGNED_CLIENT_ID} \
    --set platform.azure.tenantId=${TENANT_ID} \
    --set platform.azure.keyVaultName=${KEY_VAULT_NAME} \
    --set agent.kafka.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
    ```

  For backward compatibility, the for 0.x version, use:
    ```shell
    helm upgrade --install entitle-agent entitle/entitle-agent \
    --set platform.mode="azure" \
    --set kmsType="azure_secret_manager" \
    --set imageCredentials=${IMAGE_CREDENTIALS} \
    --set datadog.datadog.apiKey=${DATADOG_API_KEY} \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set datadog.datadog.kubelet.tlsVerify=false \
    --set datadog.datadog.kubelet.host.valueFrom.fieldRef.fieldPath="spec.nodeName" \
    --set datadog.datadog.kubelet.hostCAPath="/etc/kubernetes/certs/kubeletserver.crt" \
    --set platform.azure.clientId=${USER_ASSIGNED_CLIENT_ID} \
    --set platform.azure.tenantId=${TENANT_ID} \
    --set platform.azure.keyVaultName=${KEY_VAULT_NAME} \
    --set agent.mode=websocket \
    --set agent.websocket.token="${TOKEN}" \
    -n ${NAMESPACE} --create-namespace
    ```
    - [Why do I need to set datadog.kubelet options?](https://docs.datadoghq.com/containers/kubernetes/distributions/?tab=helm)

</details>

## Configuration

The following table lists the configurable parameters of the Entitle-agent chart and their default values.

| Parameter                         | Description                                                                                                                          | Default                           | Required input by user            |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------|-----------------------------------|
| `imageCredentials`                | Credentials you've received upon agent installation (Contact us for more info)                                                       | `null`                            | `true`                            |
| `kmsType`                         | KMS for agent to save secrets. Taken value from ["aws_secret_manager","gcp_secret_manager","azure_secret_manager","hashicorp_vault"] | `null`                            | `true`                            |
| `platform.mode`                   | Take values from: [aws,gcp,azure]                                                                                                    | `"gcp"`                           | `true`                            |
| `platform.aws.iamRole`            | IAM role for agent's service account annotations                                                                                     | `null`                            | `true` if `platform.mode="aws"`   |
| `platform.gke.serviceAccount`     | GKE service account for agent's service account annotations                                                                          | `null`                            | `true` if `mode="platform.gcp"`   |
| `platform.gke.projectId`          | GCP project ID for agent's service account annotations                                                                               | `null`                            | `true` if `mode="platform.gcp"`   |
| `platform.azure.clientId`         | Azure AD application client ID to be used with the pod (USER_ASSIGNED_CLIENT_ID from above)                                          | `null`                            | `true` if `mode="platform.azure"` |
| `platform.azure.tenantId`         | Azure AD tenant ID to be used with the pod.                                                                                          | `null`                            | `true` if `mode="platform.azure"` |
| `platform.azure.keyVaultName`     | Name of the Azure Key Vault to be used for storing the agent secrets                                                                 | `null`                            | `true` if `mode="platform.azure"` |
| `podAnnotations`                  | https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/                                                       | `{}`                              | `false`                           |
| `nodeSelector`                    | https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector                                                | `{}`                              | `false`                           |
| `global.environment`              | Used for metadata of deployment                                                                                                      | `"onprem"`                        | `false`                           |
| `agent.image.repository`          | Docker image repository                                                                                                              | `"ghcr.io/anycred/entitle-agent"` | `false`                           |
| `agent.image.tag`                 | Tag for docker image of agent                                                                                                        | `"master"`                        | `false`                           |
| `agent.mode`                      | Take values from: [kafka, websocket]                                                                                                 | `"kafka"`                         | `false`                           |
| `agent.replicas`                  | Number of pods to run                                                                                                                | `1`                               | `false`                           |
| `agent.resources.requests.cpu`    | CPU request for agent pod                                                                                                            | `"500m"`                          | `false`                           |
| `agent.resources.requests.memory` | Memory request for agent pod                                                                                                         | `"1Gi"`                           | `false`                           |
| `agent.resources.limits.cpu`      | CPU limit for agent pod                                                                                                              | `"1000m"`                         | `false`                           |
| `agent.resources.limits.memory`   | Memory limit for agent pod                                                                                                           | `"3Gi"`                           | `false`                           |
| `agent.websocket.token`           | **Deprecated** [backward compatibility] Token you've received upon agent installation (Contact us for more info)                     | `null`                            | `false`                           |
| `agent.kafka.token`               | Credentials you've received upon agent installation (Contact us for more info)                                                       | `null`                            | `true`                            |
| `datadog.providers.gke.autopilot` | Whether to enable autopilot or not                                                                                                   | `false`                           | `false`                           |
| `datadog.datadog.apiKey`          | Datadog API key                                                                                                                      | `null`                            | `true`                            |
| `datadog.datadog.tags`            | Datadog Tag - Put your company name (https://docs.datadoghq.com/tagging/)                                                            | `null`                            | `true`                            |
