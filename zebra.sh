#!/bin/bash -e
REGION=eu-west-1
CLUSTER_NAME=eks-poc
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)


AMP_IAM_ROLE_NAME=amp-iamproxy-ingest-role
AMP_SERVICE_ACCOUNT_NAME=amp-iamproxy-ingest-service-account
AMP_SERVICE_ACCOUNT_NAMESPACE=observability

EBS_CSI_SERVICE_ACCOUNT_NAME=amp-ebs-service-account
EBS_CSI_IAM_ROLE_NAME=amp-ebs-csi-iam-role


OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --region $REGION --output text | sed -e "s/^https:\/\///")


cat <<EOF > ebs-iam-role-policy_trust-relationships.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:${EBS_CSI_SERVICE_ACCOUNT_NAME}",
                    "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

echo ${OIDC_PROVIDER}

# Create IAM Role
aws iam create-role --role-name ${EBS_CSI_IAM_ROLE_NAME} --assume-role-policy-document file://ebs-iam-role-policy_trust-relationships.json

# Attach the managed EBS IAM Policy to IAM Role
aws iam attach-role-policy --role-name ${EBS_CSI_IAM_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

# Create Service Account
cat <<EOL > ebs-csi-serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EBS_CSI_IAM_ROLE_NAME}
  name: ${EBS_CSI_SERVICE_ACCOUNT_NAME}
  namespace: kube-system
EOL

kubectl apply -f ebs-csi-serviceaccount.yaml
kubectl get serviceaccount ${EBS_CSI_SERVICE_ACCOUNT_NAME} -n kube-system

# Add Helm chart repository:
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver

# Update Helm repository:
helm repo update

# Install EBS CSI driver controller:
helm upgrade --install aws-ebs-csi-driver \
  --version=2.17.1 \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set node.serviceAccount.create=false \
  --set enableVolumeScheduling=true \
  --set enableVolumeResizing=true \
  --set enableVolumeSnapshot=true \
  --set controller.serviceAccount.name=${EBS_CSI_SERVICE_ACCOUNT_NAME} \
  --set node.serviceAccount.name=${EBS_CSI_SERVICE_ACCOUNT_NAME} \
  aws-ebs-csi-driver/aws-ebs-csi-driver

# Check EBS CSI driver readiness
kubectl get pods -n kube-system -l app.kubernetes.io/component==csi-driver

# Check Storage Classes list:
kubectl get sc

# Create a namespace for AMP controller
kubectl create ns ${AMP_SERVICE_ACCOUNT_NAMESPACE}


# IAM Role for K8S service account
cat <<EOF > amp-iam-role-policy_trust-relationships.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${AMP_SERVICE_ACCOUNT_NAMESPACE}:${AMP_SERVICE_ACCOUNT_NAME}"
        }
      }
    }
  ]
}
EOF

# Create a new IAM Role
aws iam create-role --role-name ${AMP_IAM_ROLE_NAME} --assume-role-policy-document file://amp-iam-role-policy_trust-relationships.json


cat <<EOF > amp-permission_policy-ingest.json
{
    "Version":"2012-10-17",
    "Statement":[
       {
          "Effect":"Allow",
          "Action":[
             "aps:RemoteWrite",
             "aps:QueryMetrics",
             "aps:GetSeries",
             "aps:GetLabels",
             "aps:GetMetricMetadata"
          ],
          "Resource":"*"
       }
    ]
 }
EOF

# Attach an inline policy to the role
aws iam put-role-policy --role-name ${AMP_IAM_ROLE_NAME}  --policy-name AMPermissionPolicy --policy-document file://amp-permission_policy-ingest.json

# Install Prometheus Controller
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 

# The content of "amp_ingest_override_values.yaml" was directly copied from the AWS AMP workspace.
helm install prometheus-for-amp prometheus-community/prometheus -n  ${AMP_SERVICE_ACCOUNT_NAMESPACE} -f amp_ingest_override_values.yaml
# helm install prometheus-for-amp prometheus-community/prometheus -n  observability -f amp_ingest_override_values.yaml

# Check Prometheus Controller readiness
kubectl get pods -n ${AMP_SERVICE_ACCOUNT_NAMESPACE}
