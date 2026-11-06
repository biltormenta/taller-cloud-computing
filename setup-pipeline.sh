#!/bin/bash
# Crea roles IAM, proyectos CodeBuild y el pipeline (Source -> Build -> Deploy a EKS).
# Se ejecuta una sola vez en AWS CloudShell. Requiere: cluster EKS activo, repo ECR y conexion GitHub creados.
set -euo pipefail

R=us-east-1
CL=cluster-taller
ECR_REPO=taller-eks
REPO=biltormenta/taller-cloud-computing
A=$(aws sts get-caller-identity --query Account --output text)
BUCKET=taller-eks-artifacts-$A
CONN=$(aws codestar-connections list-connections --region $R --query "Connections[?ConnectionName=='taller-github'].ConnectionArn | [0]" --output text)

echo "Cuenta $A | conexion $CONN"

# Bucket de artefactos del pipeline
aws s3api head-bucket --bucket $BUCKET 2>/dev/null || aws s3api create-bucket --bucket $BUCKET --region $R

# Rol de CodeBuild
aws iam create-role --role-name taller-codebuild-role --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam put-role-policy --role-name taller-codebuild-role --policy-name taller-codebuild --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
{\"Effect\":\"Allow\",\"Action\":[\"logs:*\"],\"Resource\":\"*\"},
{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:GetObjectVersion\",\"s3:PutObject\",\"s3:GetBucketLocation\"],\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/*\"]},
{\"Effect\":\"Allow\",\"Action\":[\"ecr:GetAuthorizationToken\"],\"Resource\":\"*\"},
{\"Effect\":\"Allow\",\"Action\":[\"ecr:BatchCheckLayerAvailability\",\"ecr:InitiateLayerUpload\",\"ecr:UploadLayerPart\",\"ecr:CompleteLayerUpload\",\"ecr:PutImage\",\"ecr:BatchGetImage\",\"ecr:GetDownloadUrlForLayer\"],\"Resource\":\"arn:aws:ecr:$R:$A:repository/$ECR_REPO\"},
{\"Effect\":\"Allow\",\"Action\":[\"eks:DescribeCluster\"],\"Resource\":\"*\"}]}"

# Rol de CodePipeline
aws iam create-role --role-name taller-codepipeline-role --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codepipeline.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam put-role-policy --role-name taller-codepipeline-role --policy-name taller-codepipeline --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:GetObjectVersion\",\"s3:PutObject\",\"s3:GetBucketVersioning\"],\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/*\"]},
{\"Effect\":\"Allow\",\"Action\":[\"codebuild:StartBuild\",\"codebuild:BatchGetBuilds\"],\"Resource\":\"*\"},
{\"Effect\":\"Allow\",\"Action\":[\"codestar-connections:UseConnection\"],\"Resource\":\"$CONN\"}]}"

echo "Esperando propagacion de IAM..."; sleep 15

# Dar acceso al rol de CodeBuild dentro del cluster (EKS access entries)
CBROLE=arn:aws:iam::$A:role/taller-codebuild-role
aws eks create-access-entry --cluster-name $CL --region $R --principal-arn $CBROLE >/dev/null
aws eks associate-access-policy --cluster-name $CL --region $R --principal-arn $CBROLE \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster >/dev/null

# Proyecto CodeBuild de Build (docker build + push a ECR)
aws codebuild create-project --region $R --name taller-build \
  --source '{"type":"CODEPIPELINE","buildspec":"buildspec-build.yml"}' --artifacts '{"type":"CODEPIPELINE"}' \
  --environment "{\"type\":\"LINUX_CONTAINER\",\"image\":\"aws/codebuild/standard:7.0\",\"computeType\":\"BUILD_GENERAL1_SMALL\",\"privilegedMode\":true,\"environmentVariables\":[{\"name\":\"AWS_ACCOUNT_ID\",\"value\":\"$A\"},{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"$R\"},{\"name\":\"ECR_REPO\",\"value\":\"$ECR_REPO\"}]}" \
  --service-role $CBROLE >/dev/null

# Proyecto CodeBuild de Deploy (kubectl apply en EKS)
aws codebuild create-project --region $R --name taller-deploy \
  --source '{"type":"CODEPIPELINE","buildspec":"buildspec-deploy.yml"}' --artifacts '{"type":"CODEPIPELINE"}' \
  --environment "{\"type\":\"LINUX_CONTAINER\",\"image\":\"aws/codebuild/standard:7.0\",\"computeType\":\"BUILD_GENERAL1_SMALL\",\"environmentVariables\":[{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"$R\"},{\"name\":\"EKS_CLUSTER\",\"value\":\"$CL\"}]}" \
  --service-role $CBROLE >/dev/null

# Pipeline
cat > /tmp/pipeline.json <<EOF
{"pipeline":{"name":"taller-eks","roleArn":"arn:aws:iam::$A:role/taller-codepipeline-role","pipelineType":"V2",
"artifactStore":{"type":"S3","location":"$BUCKET"},
"stages":[
{"name":"Source","actions":[{"name":"GitHub","actionTypeId":{"category":"Source","owner":"AWS","provider":"CodeStarSourceConnection","version":"1"},
 "configuration":{"ConnectionArn":"$CONN","FullRepositoryId":"$REPO","BranchName":"main","OutputArtifactFormat":"CODE_ZIP"},"outputArtifacts":[{"name":"SourceArtifact"}]}]},
{"name":"Build","actions":[{"name":"BuildImage","actionTypeId":{"category":"Build","owner":"AWS","provider":"CodeBuild","version":"1"},
 "configuration":{"ProjectName":"taller-build"},"inputArtifacts":[{"name":"SourceArtifact"}],"outputArtifacts":[{"name":"BuildArtifact"}]}]},
{"name":"Deploy","actions":[{"name":"DeployToEKS","actionTypeId":{"category":"Build","owner":"AWS","provider":"CodeBuild","version":"1"},
 "configuration":{"ProjectName":"taller-deploy"},"inputArtifacts":[{"name":"BuildArtifact"}],"outputArtifacts":[]}]}
]}}
EOF
aws codepipeline create-pipeline --region $R --cli-input-json file:///tmp/pipeline.json --query pipeline.name --output text
echo "LISTO. Autoriza la conexion GitHub en la consola y luego: aws codepipeline start-pipeline-execution --name taller-eks"
