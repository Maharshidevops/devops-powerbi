# SI2 Tech BI & DevOps Interview Questions and Answers

Use this as a same-day revision sheet. Keep answers honest: if you have not used a tool deeply, say what you have done, what you understand, and how you would troubleshoot it.

## 1. Short Introduction

**Question:** Tell me about yourself.

**Answer:**  
I work across Business Intelligence, data pipelines, databases, and DevOps automation. My focus is building reliable analytics workflows: extracting data, validating it, loading it into relational databases, exposing dashboards, and automating deployments through CI/CD. I am comfortable with SQL, Python scripting, Git workflows, Docker-based deployments, and pipeline troubleshooting. For this role, I would connect data engineering, application, and infrastructure teams so BI platforms such as Apache Superset and workflow tools such as Airflow can run reliably across environments.

## 2. Role Understanding

**Question:** What do you understand about this BI & DevOps role?

**Answer:**  
This is a bridge role between analytics and platform engineering. The person must maintain BI platforms, orchestrate data workflows, write strong SQL and automation scripts, and also ensure deployments are repeatable using GitLab CI/CD. It is not only dashboard work; it includes production support, observability, security, release management, database performance, and documentation.

## 3. Apache Superset

**Question:** What is Apache Superset?

**Answer:**  
Apache Superset is an open-source BI and data visualization platform. It connects to databases through SQLAlchemy-supported connectors, allows users to create datasets, charts, dashboards, and SQL Lab queries, and supports role-based access control. In production, it usually needs a metadata database, Redis or cache layer, proper authentication, backups, and deployment automation.

**Question:** How would you deploy Superset on Kubernetes?

**Answer:**  
I would package Superset using Helm or Kubernetes manifests, externalize configuration through ConfigMaps and Secrets, use a managed database such as PostgreSQL for metadata, configure ingress/TLS, set resource requests and limits, and use persistent storage only where required. I would also run database migrations during deployment, configure admin bootstrapping safely, and monitor pods, logs, and health checks.

**Question:** What would you check if Superset dashboards are slow?

**Answer:**  
I would check the underlying SQL queries, database indexes, joins, filters, row counts, dashboard chart count, cache configuration, Superset worker capacity, database connection pool settings, and browser/network latency. Most BI performance problems come from inefficient SQL or missing database tuning, not only the dashboard layer.

## 4. Apache Airflow

**Question:** What is Airflow used for?

**Answer:**  
Airflow is used to author, schedule, and monitor workflows as DAGs. In BI and ETL systems, it can extract source data, run validation, transform data, load target tables, trigger reports, and send alerts on failure.

**Question:** What is a DAG?

**Answer:**  
A DAG is a Directed Acyclic Graph. In Airflow, it represents a workflow where tasks have dependencies and no circular loops. Each task should ideally be idempotent so retries do not corrupt data.

**Question:** How do you handle Airflow task failures?

**Answer:**  
I check task logs first, then validate connection credentials, input data availability, timeout settings, retries, upstream dependencies, and resource limits. For production, I configure retries, failure callbacks, alerting, SLAs where needed, and clear runbooks so support teams know what to do.

## 5. GitLab and CI/CD

**Question:** What is a CI/CD pipeline?

**Answer:**  
CI/CD automates build, test, security checks, packaging, and deployment. CI validates every change early, while CD promotes tested artifacts to environments such as dev, staging, and production using controlled rules or approvals.

**Question:** What stages would you design for this role?

**Answer:**  
I would use stages like lint, unit test, SQL validation, Docker build, security scan, deploy to dev, integration test, staging approval, production deployment, and post-deploy smoke checks. I would also store secrets in GitLab CI variables or a secrets manager, not in code.

**Question:** What branching strategy do you prefer?

**Answer:**  
For most teams I prefer trunk-based development with short-lived feature branches, merge requests, mandatory reviews, and automated pipeline checks. For stricter release teams, GitFlow can work, but it adds process overhead.

## 6. SQL, PL/SQL, and RDBMS

**Question:** How do you optimize a slow SQL query?

**Answer:**  
I start with the execution plan, check full table scans, join order, indexes, filter selectivity, stale statistics, unnecessary columns, functions on indexed columns, and large sorts. Then I test changes with realistic data volume and compare runtime and resource usage.

**Question:** Difference between stored procedure, function, and trigger?

**Answer:**  
A stored procedure performs a database operation and may not return a value. A function returns a value and can often be used inside SQL expressions depending on the database. A trigger runs automatically when an event occurs, such as insert, update, or delete.

**Question:** When should triggers be avoided?

**Answer:**  
Triggers should be avoided when they hide complex business logic, create performance issues, or make data changes hard to trace. They are useful for auditing, derived fields, and enforcing certain rules, but they must be documented clearly.

**Question:** What RDBMS differences matter in this job?

**Answer:**  
Oracle uses PL/SQL packages, sequences, hints, and strong enterprise features. PostgreSQL has PL/pgSQL, rich indexing, JSON support, and extensions. MySQL is common for web workloads. MS SQL Server uses T-SQL, SQL Server Agent, and strong integration with Microsoft tools. The SQL concepts are similar, but syntax, tuning, locking, and procedural languages differ.

## 7. Python Scripting

**Question:** How would you use Python in BI operations?

**Answer:**  
I would use Python for ETL jobs, API extraction, file validation, database loading, data quality checks, operational scripts, report generation, and Airflow DAG tasks. I would include logging, exception handling, retries, environment-based configuration, and idempotent behavior.

**Question:** How do you validate data in ETL?

**Answer:**  
I validate schema, nullability, duplicates, referential integrity, row counts, date ranges, numeric ranges, checksum totals, and business rules. I also store validation results so failures can be audited.

## 8. Node.js

**Question:** Why is Node.js useful in this role?

**Answer:**  
Node.js can be used for lightweight backend services, APIs, webhook receivers, GitLab integrations, operational tooling, and small services that expose pipeline or BI status to users.

**Question:** How would you secure a Node.js API?

**Answer:**  
I would validate input, use authentication and authorization, avoid hardcoded secrets, enable HTTPS behind a load balancer or proxy, use dependency scanning, handle errors safely, add rate limiting where required, and log important events without exposing sensitive data.

## 9. Shell Scripting

**Question:** What makes a shell script production-ready?

**Answer:**  
It should use strict mode where appropriate, validate inputs, check exit codes, log meaningful messages, avoid hardcoded secrets, be idempotent, and fail safely. For Bash, I usually use `set -euo pipefail` carefully and test scripts in non-production first.

## 10. Docker and Kubernetes

**Question:** Why use containers?

**Answer:**  
Containers make applications portable and repeatable by packaging the runtime, dependencies, and application code. They help reduce environment mismatch between development, testing, and production.

**Question:** What Kubernetes objects are important for Superset or Airflow?

**Answer:**  
Deployments, Services, ConfigMaps, Secrets, Ingress, PersistentVolumeClaims, Jobs, CronJobs, ServiceAccounts, and HorizontalPodAutoscalers are common. For Airflow, workers, scheduler, webserver, metadata database, and logs need careful design.

**Question:** Is AWS EKS free tier?

**Answer:**  
No. EKS control plane usage is normally billable. For a free-tier-friendly demo, I would use Docker Compose or a lightweight single-node Kubernetes distribution on a free-tier-eligible EC2 instance. For production, I would use EKS with proper cost planning.

## 11. AWS and Infrastructure

**Question:** Which AWS services are useful for this role?

**Answer:**  
EC2 for compute, S3 for object storage, RDS for managed databases, IAM for access control, CloudWatch for logs and metrics, ECR for container images, Secrets Manager or SSM Parameter Store for secrets, and EKS for managed Kubernetes when budget and production needs justify it.

**Question:** How do you avoid unexpected AWS charges?

**Answer:**  
I create budgets and billing alerts, use free-tier-eligible resources only, stop or terminate unused resources, avoid NAT Gateways for demos, avoid oversized RDS or EC2 instances, review CloudWatch logs retention, and tag resources for ownership and cleanup.

## 12. Terraform and IaC

**Question:** What is Infrastructure as Code?

**Answer:**  
Infrastructure as Code means defining infrastructure in version-controlled files instead of creating it manually. It improves repeatability, reviewability, rollback, and environment consistency.

**Question:** What Terraform commands do you commonly use?

**Answer:**  
`terraform init`, `terraform fmt`, `terraform validate`, `terraform plan`, `terraform apply`, and `terraform destroy`.

## 13. Monitoring and Logging

**Question:** What would you monitor in CI/CD and BI platforms?

**Answer:**  
Pipeline success rate, deployment duration, failed jobs, Airflow DAG failures, task duration, Superset response time, database CPU and connections, query latency, disk usage, memory, container restarts, and error logs.

## 14. Production Support

**Question:** A pipeline failed during production support. What do you do?

**Answer:**  
I first assess impact, check alerts and logs, identify the failed stage or task, confirm whether it is data, code, infra, or credential related, apply the runbook, communicate status, restore service or rerun safely, and document root cause and prevention steps afterward.

## 15. Scenario Questions

**Question:** Airflow DAG succeeded, but dashboard data is missing. What could be wrong?

**Answer:**  
The DAG may have loaded zero rows, loaded the wrong partition, failed validation silently, written to the wrong schema, or Superset may be using cached results. I would check row counts, target tables, DAG logs, data timestamps, SQL filters, and dashboard cache.

**Question:** GitLab pipeline passes in dev but fails in production deployment. Why?

**Answer:**  
Common causes are different environment variables, secrets, network access, permissions, image tags, database migrations, resource limits, or manual configuration drift. I would compare environment configuration and review deployment logs.

**Question:** Database CPU is high after a new dashboard release. What do you do?

**Answer:**  
I identify heavy queries, check dashboard filters and chart count, inspect execution plans, add or adjust indexes if justified, enable caching, limit default date ranges, and coordinate with users if a dashboard design change is needed.

## 16. Smart Questions to Ask Interviewer

- What BI platforms and databases are currently used at SI2 Tech?
- Is Superset deployed on EKS, on-prem Kubernetes, or both?
- How mature are the current GitLab CI/CD pipelines?
- What are the biggest pain points: deployment reliability, data quality, dashboard performance, or production support?
- Which cloud platform is most used by the team?
- How are incidents, runbooks, and SLAs managed?

## 17. Honest Closing Statement

I am strongest where BI, SQL, automation, and deployment workflows meet. If I do not know an environment-specific detail, I investigate through logs, documentation, and controlled testing instead of guessing. I care about reliable systems, clear documentation, and making analytics platforms easier for teams to operate.

