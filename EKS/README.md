# AWS EKS security check
aws install guide - https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/getting-started-install.html

## Pre install

```
# jq
sudo apt update
suao apt instasll jq
jq --version

# AWS CLI
sudo apt-get update
sudo apt-get install unzip -y

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

## How to

```
# Make eks_audit.sh File

# Configure your CLUSTER_NAME and REGION on eks_audit.sh

# Configure permission on eks_audit.sh

# Execute eks_audit.sh
```
