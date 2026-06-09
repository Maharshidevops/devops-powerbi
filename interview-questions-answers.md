# Interview Questions and Answers

Below is a human-style interview prep sheet based on the repository artifacts.
I kept the answers practical, direct, and easy to say out loud.

---

## Q1. A Linux server is slow and CPU is high. How do you find the culprit?

I usually stop relying on `top` alone and switch to `ps` so I can sort by CPU.
I'd run `ps aux --sort=-%cpu | head -20` to identify the top consumer, then inspect the PID with `/proc`, `lsof`, or `strace` depending on what the process is doing. If it's a Python service, I'd reach for `py-spy` because it shows the actual Python call stack without restarting the app.
My rule is to terminate gently first with `SIGTERM`, and only use `SIGKILL` if the process refuses to exit.

## Q2. What does `chmod 777` mean, and why is it risky?

`777` means everyone can read, write, and execute the file. That is almost always too open for production.
If a config file or secret file has `777`, any local user or compromised service could read or modify it. In production I'd rather use something like `640` or `600`, owned by the correct user and group, and keep secrets in a proper secret manager instead of a plain file.

## Q3. An app is supposed to listen on port 8080, but connections are refused. How do you debug it?

I'd check three things: whether the app is actually listening on `8080`, whether another process took the port, and whether network policy is blocking it.
`ss -tlnp | grep 8080` tells me if the process bound the port. If it's only bound to `127.0.0.1`, remote traffic will still fail. Then I'd verify security groups, firewalls, and NACLs if this is on AWS. The key is to separate "app issue" from "network issue" quickly.

## Q4. How do you find error log lines from the last 10 minutes but exclude health checks?

I'd use `awk` for time filtering and pattern matching, or `rg`/CloudWatch Logs Insights if the logs are large or centralized.
For example, on a Linux box I'd look for `ERROR` lines newer than a timestamp cutoff and ignore anything containing `healthcheck`. In AWS, Logs Insights is usually the fastest way because it lets me filter and sort without downloading logs first.

## Q5. A cron job silently stopped producing output. Where do you look first?

First I check whether cron actually ran and whether the cron service is healthy.
Then I look at the environment the job runs with, because cron is very minimal compared to an interactive shell. Missing env vars, the wrong Python interpreter, and relative paths are the usual suspects. I also make sure stdout and stderr are redirected to a log file so failures are visible instead of silent.

## Q6. Explain your VPC design for this platform.

I designed it as a two-AZ VPC with public, private app, and private data subnets.
The ALB sits in public subnets, ECS Fargate tasks run in private app subnets, and RDS Postgres lives in private data subnets. I also use NAT Gateways per AZ for outbound access, plus VPC endpoints so private services can reach AWS services without exposing traffic to the public internet. The overall idea is to keep internet entry points small and the data layer isolated.

## Q7. How do private ECS tasks talk to S3 and SQS without a NAT Gateway?

For S3, I'd use a Gateway VPC endpoint, because it's free and integrates with route tables.
For SQS, I'd use an Interface endpoint / PrivateLink. That costs money, but it still keeps traffic on the AWS backbone and avoids NAT data charges. It's both cheaper at scale and better from a security standpoint because the traffic never needs to leave the AWS network.

## Q8. What are the first bottlenecks you'd expect at 500,000 concurrent users?

My first three concerns would be RDS connections, Redis pressure, and background queue backlog.
For RDS I'd watch `DatabaseConnections` and `CPUUtilization`, then use something like RDS Proxy to reduce connection churn. For Redis I'd watch `EngineCPUUtilization` and evictions, then scale or split read-heavy traffic. For SQS I'd watch queue depth and age of oldest message, then scale workers based on backlog rather than just CPU. I like to alert before users feel the issue, not after.

## Q9. Name three concrete security controls inside ECS or EKS.

First, I'd scope IAM task roles to least privilege so each service only gets the permissions it truly needs.
Second, I'd segment services with security groups so only the intended traffic paths are allowed.
Third, I'd enforce image scanning in CI/CD so vulnerable container images never reach production. Those three controls stop credential overreach, lateral movement, and known-vulnerability exposure.

## Q10. How would you describe the Terraform environment you built?

It's a production-style AWS stack with a VPC, subnets across two AZs, NAT Gateways, VPC endpoints, security groups, Secrets Manager, multi-AZ RDS Postgres, ECS Fargate, an ALB, logging, and autoscaling.
I also made sure the ECS task definition uses non-root execution, read-only filesystem settings, secrets injection, and health checks. The main design goal was to make the platform secure, scalable, and maintainable rather than just "working."

## Q11. How did you keep the React Docker image under 150 MB and non-root?

I used a multi-stage build.
The first stage builds the app with Node, and the second stage serves only the compiled static assets from `nginx:alpine`. That keeps the final image small because none of the build tooling, dependencies, or source code ship to production. I also run the container as the built-in non-root `nginx` user.

## Q12. Your ECS task role can read every secret in the account. How do you fix it?

I would scope the IAM policy to the exact secret ARN instead of using `"*"`.
That way the task can only read the secret it actually needs, not every secret in the account. I'd also add an IaC security scan in CI so wildcard IAM policies get caught before deployment.

## Q13. How does your GitHub Actions pipeline handle development and staging?

It builds and pushes the image, scans it, deploys automatically to development, waits for a smoke test, then pauses for manual approval before staging.
I like that flow because dev gets fast feedback, staging stays controlled, and the deployment artifact is the exact same image SHA all the way through. I also use GitHub OIDC instead of long-lived AWS keys, which is much safer and easier to manage.

## Q14. How does the scheduled scale up/down script work?

It uses EventBridge cron rules to trigger a Lambda twice a day.
At 8 PM IST it scales ECS to zero and stops RDS; at 8 AM IST it starts RDS first and then scales ECS back up to two tasks. I chose Lambda and EventBridge because it's reliable, cheap, and much better than maintaining a dedicated cron server just for this one job.

## Q15. It's 11 PM and the video upload service is returning 500s. What do you do first?

I start by confirming scope: whether the error rate is real, when it started, and whether it looks like a sudden spike or a gradual degradation.
Then I check CloudWatch Logs and ECS service health because I can't SSH into Fargate. After that I look at the database, service counts, and recent deployment signals. In the first five minutes, my goal is to form a hypothesis fast enough to stop guessing and start narrowing the fault.

## Q16. AWS costs jumped 40% month-over-month. How do you find and fix it?

I'd start in Cost Explorer and group by service, then drill into usage type and tags.
For a video platform, the likely culprits are S3 transfer, CloudFront cache misses, or oversized Fargate tasks. Once I fix the source, I'd add guardrails like cost anomaly detection, budget alerts, and IaC cost checks so the problem doesn't sneak back in quietly.

---

## Quick closing summary

If I had to summarize the whole project in one sentence, I'd say:
**it's a secure, production-minded AWS platform with clean separation between web, app, and data layers, plus strong CI/CD and operational guardrails.**
