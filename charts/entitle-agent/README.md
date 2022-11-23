Entitle Agent
===========

A Helm Chart for Entitle's Agent.

## Pre-Install

```shell
helm dependency update charts/entitle-agent
helm dependency build charts/entitle-agent
helm repo add datadog https://helm.datadoghq.com
helm repo add entitle https://anycred.github.io/entitle-charts/
```

### GCP installation

#### A. Workload Identity

**Notice:** If you installed our IaC then you may now skip to the [chart installation part](#gcp-chart-installation).

Follow the following GCP (GKE) guides:

- [Google Kubernetes Engine (GKE) > Documentation > Guides > About Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
- [Google Kubernetes Engine (GKE) > Documentation > Guides > Use Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

In the step "**Configure applications to use Workload Identity**", use the following roles for the gcp service account:

- `roles/secretmanager.admin`
- `roles/iam.securityAdmin`
- `roles/container.developer`
- `roles/iam.workloadIdentityUser`

#### B. Update `kubeconfig`

* If you have installed Entitle's Terraform IaC:

  You can set the environment variables using terraform output file `terraform_output.json`:
    ```shell
    BASTION_HOSTNAME=$(jq -r '.bastion_hostname.value' terraform_output.json)
    PROJECT_ID=$(jq -r '.project_id.value' terraform_output.json)
    ZONE=$(jq -r '.zone.value' terraform_output.json)
    CLUSTER_NAME=$(jq -r '.cluster_name.value' terraform_output.json)
    ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME=$(jq -r '.entitle_agent_gke_service_account_name.value' terraform_output.json)
    TOKEN=$(jq -r '.token.value' terraform_output.json)
    COSTUMER_NAME=$(jq -r '.costumer_name.value' terraform_output.json)
    NAMESPACE=$(jq -r '.namespace.value' terraform_output.json)
    IMAGE_CREDENTIALS=$(jq -r '.image_credentials.value' terraform_output.json)
    DATADOG_API_KEY=$(jq -r '.datadog_api_key.value' terraform_output.json)
    BASTION_SETUP_COMMAND=$(jq -r '.bastion_setup_command.value' terraform_output.json)
    AUTOPILOT=$(jq -r '.autopilot.value' terraform_output.json)
    ```

  #### Setting up IAP-tunnel:
    ```shell
    gcloud beta compute ssh "<BASTION_HOSTNAME>" --tunnel-through-iap --project "<PROJECT_ID>" --zone "<ZONE>" -- -4 -N -L 8888:127.0.0.1:8888 -o "ExitOnForwardFailure yes" -o "ServerAliveInterval 10" &
    ```

  If your cluster isn't configured on kubeconfig yet:
    ```shell
    gcloud container clusters get-credentials "<CLUSTER_NAME>" --zone "<ZONE>" --project "<PROJECT_ID>" --internal-ip
    ```

* Otherwise, simply replace `<CLUSTER_NAME>` and `<ZONE>` and run the following command:
    ```shell
    gcloud container clusters get-credentials <CLUSTER_NAME> --zone <ZONE>
    ```

#### C. [GCP Chart Installation](https://helm.sh/docs/helm/helm_upgrade/)
- `imageCredentials` and `agent.kafka.token` are given to you by Entitle
- Replace `<YOUR_ORG_NAME>` in `datadog.tags` to your company name

- If you have installed Entitle's Terraform IaC, you need to set up proxy(after [Setting up IAP-tunnel](#setting-up-iap-tunnel)):

```shell
export HTTPS_PROXY=localhost:8888
```

```shell
helm upgrade --install entitle-agent entitle/entitle-agent \
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
  --set imageCredentials="${IMAGE_CREDENTIALS}" \
  --set datadog.datadog.apiKey="${DATADOG_API_KEY}" \
  --set datadog.providers.gke.autopilot="${AUTOPILOT}" \
  --set platform.gke.serviceAccount="${ENTITLE_AGENT_GKE_SERVICE_ACCOUNT_NAME}" \
  --set platform.gke.projectId="${PROJECT_ID}" \
  --set agent.kafka.token="${TOKEN}" \
  --set datadog.datadog.tags={company:${ORGANIZATION_NAME}} \
  -n "${NAMESPACE}" --create-namespace
```

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

<details>
  <summary>Create policy</summary>

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

</details>

<details>
<summary>Create IAM role and attach policy</summary>

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

</details>

### [Chart Installation](https://helm.sh/docs/helm/helm_upgrade/)

Eventually, you can install our Helm chart:
- `imageCredentials` and `agent.kafka.token` are given to you by Entitle
- Replace `platform.aws.iamRole` with Entitle's AWS IAM Role you've created
- Replace `<YOUR_ORG_NAME>` in `datadog.tags` to your company name

```shell
export IMAGE_CREDENTIALS=<IMAGE_CREDENTIALS_FROM_ENTITLE>
export DATADOG_API_KEY=<DATADOG_API_KEY_FROM_ENTITLE>
export TOKEN=<TOKEN_FROM_ENTITLE>
export ORG_NAME=<YOUR ORGANIZATION NAME>

helm upgrade --install entitle-agent entitle/entitle-agent \
    --set imageCredentials=${IMAGE_CREDENTIALS} \
    --set datadog.datadog.apiKey=${DATADOG_API_KEY} \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set platform.aws.iamRole="arn:aws:iam::${ACCOUNT_ID}:role/entitle-agent-role" \
    --set agent.kafka.token="${TOKEN}" \
    -n entitle --create-namespace
```

For backward compatibility, the for 0.x version, use:
```shell
export IMAGE_CREDENTIALS=<IMAGE_CREDENTIALS_FROM_ENTITLE>
export DATADOG_API_KEY=<DATADOG_API_KEY_FROM_ENTITLE>
export TOKEN=<TOKEN_FROM_ENTITLE>
export ORG_NAME=<YOUR ORGANIZATION NAME>

helm upgrade --install entitle-agent entitle/entitle-agent \
    --set imageCredentials=${IMAGE_CREDENTIALS} \
    --set datadog.datadog.apiKey=${DATADOG_API_KEY} \
    --set datadog.datadog.tags={company:${ORG_NAME}} \
    --set platform.aws.iamRole="arn:aws:iam::${ACCOUNT_ID}:role/entitle-agent-role" \
    --set agent.mode=websocket \
    --set agent.websocket.token="${TOKEN}" \
    -n entitle --create-namespace
```

<br /><br />
You are ready to go!

## Configuration

The following table lists the configurable parameters of the Entitle-agent chart and their default values.

| Parameter                         | Description                                                                                                      | Default       | Required input by user          |
|-----------------------------------|------------------------------------------------------------------------------------------------------------------| ------------- |---------------------------------|
| `imageCredentials`                | Credentials you've received upon agent installation (Contact us for more info)                                   | `null` | `true`                          |
| `platform.mode`                   |                                                                                                                  | `"gcp"` | `true`                          |
| `platform.aws.iamRole`            | IAM role for agent's service account annotations                                                                 | `null` | `true` if `platform.mode="aws"` |
| `platform.gke.serviceAccount`     | GKE service account for agent's service account annotations                                                      | `null` | `true` if `mode="platform.gcp"` |
| `platform.gke.projectId`          | GCP project ID for agent's service account annotations                                                           | `null` | `true` if `mode="platform.gcp"` |
| `podAnnotations`                  | https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/                                   | `{}` | `false`                         |
| `nodeSelector`                    | https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector                            | `{}` | `false`                         |
| `global.environment`              | Used for metadata of deployment                                                                                  | `"onprem"` | `false`                         |
| `agent.image.repository`          | Docker image repository                                                                                          | `"ghcr.io/anycred/entitle-agent"` | `false`                         |
| `agent.image.tag`                 | Tag for docker image of agent                                                                                    | `"master"` | `false`                         |
| `agent.mode`                      | Take values from: [kafka, websocket]                                                                             | `"kafka"` | `false`                         |
| `agent.replicas`                  | Number of pods to run                                                                                            | `1` | `false`                         |
| `agent.resources.requests.cpu`    | CPU request for agent pod                                                                                        | `"500m"` | `false`                         |
| `agent.resources.requests.memory` | Memory request for agent pod                                                                                     | `"1Gi"` | `false`                         |
| `agent.resources.limits.cpu`      | CPU limit for agent pod                                                                                          | `"1000m"` | `false`                         |
| `agent.resources.limits.memory`   | Memory limit for agent pod                                                                                       | `"3Gi"` | `false`                         |
| `agent.websocket.token`           | **Deprecated** [backward compatibility] Token you've received upon agent installation (Contact us for more info) | `null` | `false`                         |
| `agent.kafka.token`               | Credentials you've received upon agent installation (Contact us for more info)                                   | `null` | `true`                          |
| `datadog.providers.gke.autopilot` | Whether to enable autopilot or not                                                                               | `false` | `false`                         |
| `datadog.datadog.apiKey`          | Datadog API key                                                                                                  | `null` | `true`                          |
| `datadog.datadog.tags`            | Datadog Tag - Put your company name (https://docs.datadoghq.com/tagging/)                                        | `null` | `true`                          |
