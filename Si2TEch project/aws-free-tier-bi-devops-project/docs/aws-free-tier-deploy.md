# AWS Free-Tier-Friendly Deployment Guide

This guide is intentionally conservative. It avoids services that commonly surprise beginners with charges.

## Recommended Demo Deployment

Use a single free-tier-eligible EC2 instance and Docker Compose.

Suggested AWS services:

- **EC2:** one small free-tier-eligible Linux instance, depending on your account type and region.
- **EBS:** keep disk small and delete unused volumes.
- **Security Group:** allow SSH from your IP only; expose app ports only when needed.
- **CloudWatch:** use basic monitoring and set log retention if you ship logs.
- **AWS Budgets:** create a zero or low-cost alert before deploying.

## Avoid for Free-Tier Demo

- **EKS:** production-relevant, but the control plane is normally billable.
- **NAT Gateway:** useful in production, but not free-tier-friendly.
- **Large RDS instances:** use local Postgres for this demo unless your account clearly includes credits or eligible RDS usage.
- **Elastic IP left unattached:** can create charges.

## EC2 Setup Outline

```bash
sudo dnf update -y || sudo apt-get update -y
sudo dnf install -y git docker || sudo apt-get install -y git docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user || sudo usermod -aG docker ubuntu
```

Log out and log back in so Docker group membership applies.

```bash
git clone <your-repo-url>
cd aws-free-tier-bi-devops-project
cp .env.example .env
docker compose up -d postgres
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python etl/validate_sales.py data/sample_sales.csv
python etl/load_sales.py data/sample_sales.csv
```

## Interview Explanation

Say this clearly:

> For a cost-safe portfolio demo, I use Docker Compose on one small EC2 instance. In production, I would move metadata and analytics databases to RDS, push images to ECR, run Superset or Airflow on EKS if required, and add CloudWatch, Prometheus, Grafana, IAM least privilege, backups, and proper secret management.

## Cleanup Checklist

- Stop Docker containers.
- Terminate EC2.
- Delete unattached EBS volumes.
- Delete snapshots if created.
- Release unused Elastic IPs.
- Confirm AWS Budgets and Billing show no unexpected active resources.

