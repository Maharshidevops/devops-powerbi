# Final Assessment Submission

This repository contains my responses and implementation artifacts for the infrastructure/platform assessment.

# Repository Structure

- `answer1.md`: Written answers for Q1-Q16 (with references to folder-based deliverables where applicable).
- `architecture/Architecture.png`: VPC and platform architecture diagram (Q6).
- `q10/`: Terraform template for a production-ready AWS environment (Q10).
  - `main.tf`
  - `variables.tf`
  - `outputs.tf`
  - `terraform.tfvars.example`
- `q-11/`: Docker setup for React frontend (Q11).
  - `Dockerfile`
  - `nginx.conf`
  - `.dockerignore`
- `q13/`: CI/CD pipeline for Development and Staging deployments (Q13).
  - `deploy.yml`
  - `secrets-setup.md`
- `q14/`: ECS and RDS scheduled scale/start-stop solution (Q14).
  - `lambda/scheduler.py`
  - `terraform/eventbridge.tf`
  - `written-answer.md`

# Question-to-Answer Mapping

- Q1-Q5, Q7-Q9, Q12, Q15, Q16: Available in `answer1.md`.
- Q6: Architecture diagram in `architecture/Architecture.png` (referenced from `answer1.md`).
- Q10: Terraform implementation in `q10/`.
- Q11: Docker implementation in `q-11/`.
- Q13: Pipeline implementation in `q13/`.
- Q14: Scheduling script and infra in `q14/`.

# Notes

- This submission mixes written operational answers and runnable IaC/application artifacts.
- File and folder names are kept aligned with question numbers for quick review.