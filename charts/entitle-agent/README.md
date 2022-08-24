# Entitle Agent Helm Chart

## Introduction

This Helm chart guide will take you through the installation of Entitle agent on your cluster.

## What the helm comprised of :

* Keys to pull the docker image of our agent from github container registry.
* DataDog helm chart that will help us help you :)
* New namespace.
* Deployment roles and other kubernetes CRD.

## Prerequisites:

* Kubernetes cluster to run our helm on - Entitle agent needs its own namespace (we create one in the chart) so we can
  run with other tools in a friendly manner
    * **NOTICE:** if you don't have an existing kubernetes cluster it is recommended to use our IAC to deploy one
      including the roles/annotations
* ability to read and write to KMSs
    * We have our own guide/IAC for each cloud provider in order to give access to the Entitle agent

## First run

```shell
helm dependency update ./
helm dependency build ./
```

## Amazon installation

### First things first:

1. Define bash variable for `CLUSTER_NAME`:
   `CLUSTER_NAME=<your-cluster-name>`

2. Update kubeconfig:
   `aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-2 # Or any other region`

**Notice:** If you installed our IAC then you may now skip to the [chart installation part](#chart-installation)

### [Create OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

You can check if you already have the identity provider for your cluster using one of the following:

- Run this command:
  `aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text`
- Or [here](https://us-east-1.console.aws.amazon.com/iamv2/home?region=us-east-1#/identity_providers).

If you don't have an OIDC provider, please create new one:
`eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve`

### [Create IAM Policy and Role](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html)

<details>
  <summary>Create policy</summary>

  ```shell
  ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  echo $ACCOUNT_ID

  cat > entitle-entitle-agent-chart-policy.json <<ENDOF
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

  aws iam create-policy --policy-name entitle-entitle-agent-policy --policy-document file://entitle-entitle-agent-policy.json
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
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:entitle:entitle-agent"
        }
      }
    }
  ]
}
ENDOF

aws iam create-role --role-name entitle-entitle-agent-chart-role --assume-role-policy-document file://trust.json --description "entitle entitle-agent access aws"
aws iam attach-role-policy --role-name entitle-entitle-agent-chart-role --policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/entitle-entitle-agent-chart-policy
```

</details>


**Eventually you can helm install our chart:**

### [Chart Installation](https://helm.sh/docs/helm/helm_upgrade/)

- Replace `serviceAccount.iamrole` with `secretsmanager_role_arn` from the terraform output if you installed our IAC
- Replace `<DATADOG_CUSTOMER_ID>` in `datadog.tags` to your company name

```shell
helm upgrade --install entitle-agent-chart ./ \
    --set dockerConfigJson="<BASE64_ENCODED_DOCKER_CONFIG_JSON>" \
    --set datadog.datadog.apiKey="<DATADOG_API_KEY>" \
    --set datadog.clusterAgent.metricsProvider.enabled=true \
    --set serviceAccount.iamrole="arn:aws:iam::<ACCOUNT_ID>:role/entitle--agent-role" \
    --set entitleAgent.env.KMS_TYPE="aws_secret_manager" \
    -n entitle --create-namespace
```

#### Adding your app token to Kubernetes secrets:

```shell
echo -n '{"entitle-app-token":"<YOUR_APP_TOKEN>"}' > entitle-app-token # The file name must have this name
kubectl create secret generic entitle-secret --from-file=./entitle-app-token --namespace entitle
```

You are ready to go!

# GCP Installation

## Workload Identity

**Notice:** If you installed our IAC then you may now skip to the [chart installation part](#chart-installation)

Read:

- https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity

- https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity

In step **Configure applications to use Workload Identity** use the following roles:

- "roles/secretmanager.admin",
- "roles/iam.securityAdmin"

## Update kubeconfig:

If you just installed the Terraform you may run:
`gcloud container clusters get-credentials $(terraform output -raw kubernetes_cluster_name) --region $(terraform output -raw region)`

Otherwise, simply replace `<CLUSTER_NAME>` and `<REGION>` and run the following command:
```gcloud container clusters get-credentials <CLUSTER_NAME> --region <REGION>```

## Chart installation

- Replace `<DATADOG_CUSTOMER_ID>` in `datadog.tags` to your company name

```shell
helm upgrade --install entitle-agent-chart ./ \
    --set dockerConfigJson="<BASE64_ENCODED_DOCKER_CONFIG_JSON>" \
    --set datadog.datadog.apiKey="<DATADOG_API_KEY>" \
    --set datadog.clusterAgent.metricsProvider.enabled=true \
    --set entitleAgent.env.KMS_TYPE=gcp_secret_manager \
    --set entitleAgent.serviceAccountName=entitle-agent \
    -n entitle --create-namespace
```
