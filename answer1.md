Q1.  A server is responding slowly. You log in and run top. CPU is at 95%, but you 
cannot immediately tell which process is the culprit because several look similar. 
What do you do next?

ans. Shift from top to ps for sortable output:

bash
ps aux --sort=-%cpu | head -20


Once I spot the PID, I dig into what it's actually doing:

bash
cat /proc/<PID>/cmdline | tr '\0' ' '   #exact command + args
strace -p <PID> -e trace=all -c         #syscall summary
lsof -p <PID> | head -30                #open files/sockets


Kill decision: SIGTERM first, wait 5s, then SIGKILL only if needed. Never SIGKILL a DB process without checking open transactions.

  If it's a Python pipeline   → py-spy:
bash
pip install py-spy
py-spy top --pid <PID>       #live flamegraph in terminal
py-spy dump --pid <PID>      #snapshot current call stack

py-spy attaches without restarting the process and shows exactly which Python function is spinning  far more useful than strace for Python-specific bottlenecks.



Q2. You find a file on a Linux server with permissions set to 777. What does that 
actually mean, and why is it a problem in a production environment?

ans. chmod 777 = rwxrwxrwx  owner, group, and every other user can read, write, execute.

  Realistic scenario:   /opt/app/config/db.env holds DB_PASSWORD=prod_secret and is set 777. The app runs as appuser, nginx as www-data. A path traversal bug lets an attacker read arbitrary files  they hit ../../config/db.env and get the DB password. Game over.

  Fix:  
bash
chmod 640 /opt/app/config/db.env     #owner rw, group r, world nothing
chown appuser:appgroup /opt/app/config/db.env

#For shell scripts:
chmod 750 /opt/app/scripts/deploy.sh
chown appuser:appgroup /opt/app/scripts/deploy.sh

For a credentials file in prod I'd go 600 and use Secrets Manager instead of a flat file entirely.


Q3.  Your application is supposed to be listening on port 8080, but connections are 
being refused. The process appears to be running. How do you diagnose this?

ans. Three distinct failure modes:

  1 – Process not bound to 8080:  
bash
ss -tlnp | grep 8080

If empty, process either crashed before binding or is bound to 127.0.0.1:8080 (loopback only). Check app config for server.host or bind settings.

  2 – Different process grabbed the port:  
bash
fuser 8080/tcp    #shows PID owning the port

If PID doesn't match my app, something else stole it.

  3 – Firewall silently dropping traffic:  
bash
iptables -L INPUT -n | grep -E '8080|DROP|REJECT'
firewall-cmd --list-all                          #firewalld (RHEL)

#On AWS  check Security Group AND Network ACL separately
aws ec2 describe-security-groups --group-ids <sg-id>
nc -zv <server-ip> 8080                          #test from outside

NACLs are stateless and often the culprit when SGs look fine.



Q4. You need to find all log lines from /var/log/app.log that contain the word ERROR, 
occurred in the last 10 minutes, and do not include the string healthcheck. Write the 
command.

ans.
bash
awk -v d="$(date -d '10 minutes ago' '+%Y-%m-%d %H:%M')" \
  '$0 > d && /ERROR/ && !/healthcheck/' /var/log/app.log


  Speed up 20GB file:   Use ripgrep instead of grep:
bash
rg "ERROR" /var/log/app.log | grep -v healthcheck

rg uses memory-mapped I/O and SIMD instruction sets  typically 3–5x faster than GNU grep on large files. If rg isn't available, grep -F (fixed string, no regex engine) is the next best option.

  CloudWatch Logs query:  

fields @timestamp, @message
| filter @message like /ERROR/
| filter @message not like /healthcheck/
| filter @timestamp > ago(10m)
| sort @timestamp desc
| limit 500




Q5. You have a Python script that automates a nightly infrastructure health check. It 
runs via cron at midnight but has silently stopped producing output. Nobody 
changed the script. Where do you look first?

ans. If a Python cron job suddenly stops producing output, the first thing I check is whether the cron job actually ran at all. On RHEL or Ubuntu, I usually verify cron logs first.

For Ubuntu:

grep CRON /var/log/syslog

For RHEL:

grep CRON /var/log/cron

I also check whether the cron service itself is running:

systemctl status cron

or on RHEL:

systemctl status crond

The three most common reasons I’ve seen for Python cron jobs failing silently are:

Missing environment variables because cron runs with a minimal shell environment.
Wrong Python interpreter being used instead of the application virtual environment.
Relative file paths causing config or dependency files to not be found.

To debug properly, I redirect both stdout and stderr to a log file:

/opt/app/venv/bin/python /opt/app/healthcheck.py >> /var/log/app/healthcheck.log 2>&1

To make silent failures impossible going forward, I add heartbeat monitoring so alerts trigger automatically if the cron job fails:

/opt/app/venv/bin/python /opt/app/healthcheck.py >> /var/log/app/healthcheck.log 2>&1 && curl -fsS https://hc-ping.com/<uuid> > /dev/null

If the script fails, the heartbeat is missed and monitoring alerts the team immediately.


Q6.  Draw and explain your VPC design for this platform. 
Your architecture must handle the React frontend, backend API services, an AI recommendation 
pipeline, and a video processing queue. Include: subnet layout across two AZs, where each service 
lives (ECS Fargate or EKS, RDS Postgres, ElastiCache Redis, S3, Lambda, SQS), and how traffic 
flows from a user’s browser to the database. A rough hand-drawn or Lucidchart diagram is fine  
attach it to your submission. Walk us through one complete data flow (e.g., user uploads a video) to 
prove the design works end-to-end. 

ans. Architecture folder

Q7.  Your ECS tasks run in a private subnet and need to talk to S3 and SQS without 
going through a NAT Gateway. How do you set that up, and why does it matter?


ans.  S3   → Gateway Endpoint (free, routes via route table)
      SQS   → Interface Endpoint / PrivateLink (~$7/month per AZ + $0.01/GB)

Gateway endpoints are free. Interface endpoints cost money but are still cheaper than NAT Gateway ($0.045/GB) at any meaningful volume.

  Security risk eliminated:   NAT puts traffic on the public internet even when talking to AWS services. VPC endpoints keep all traffic on AWS's private backbone  it never touches the internet. This also closes a lateral movement path where a compromised container could exfiltrate data via NAT to an external IP.

  Security group changes:  

ECS Task SG:  egress  → sg-endpoints, port 443
Endpoint SG:  ingress ← sg-ecs-tasks, port 443

Remove 0.0.0.0/0:443 egress from ECS tasks  S3/SQS traffic no longer needs it.


Q8.  The platform needs to handle 500,000 concurrent users during a live event. Walk 
us through where you expect the system to break first, and what you do about it. 
Pick the three services in your architecture that are the most likely bottlenecks under a sudden traffic 
spike. For each one, name the specific AWS metric you would watch and the specific action you 
would take not a general “add more instances” answer. Then explain how your CloudWatch 
alerting would tell you a bottleneck is forming before users start seeing errors.


ans. 1. Bottleneck: RDS Postgres Connection Exhaustion
   - Metric to watch: 'DatabaseConnections' and 'CPUUtilization'
   - Action: Under sudden load, thousands of containers will attempt to open DB connections, maxing out Postgres connection slots and thrashing the CPU. I would implement AWS RDS Proxy to pool and multiplex database connections before they hit RDS.
   - Alerting: CloudWatch alarm on 'DatabaseConnections > 80%' of the DB parameter limit. This tells me we are running out of slots before the application starts throwing 500 DB connection errors to users.

2 Bottleneck: ElastiCache Redis CPU limits
   - Metric to watch: 'EngineCPUUtilization' (Redis is single-threaded, so this is critical) and 'Evictions'.
   - Action: If the AI pipeline and frontend are hammering Redis for reads, the single thread will max out. I would scale out by adding Read Replicas to the Redis cluster and routing read-heavy queries to the replica endpoints, preserving the primary node for writes.
   - Alerting: CloudWatch alarm on 'EngineCPUUtilization > 75%'.

3 Bottleneck: SQS Video Processing Backlog
   - Metric to watch: 'ApproximateNumberOfMessagesVisible' and 'ApproximateAgeOfOldestMessage'.
   - Action: If 500k users suddenly trigger background tasks, the queue depth will spike faster than ECS/Lambda can naturally scale. I would adjust the Target Tracking Scaling Policy for the ECS worker service to scale based on a custom "Backlog per Task" metric (Queue Depth / Number of Running Tasks), ensuring we aggressively provision workers before the queue ages out.
   - Alerting: CloudWatch alarm on 'ApproximateAgeOfOldestMessage > 120 seconds'. This indicates our processing workers have fallen behind the ingestion rate.



Q9.  List three concrete security controls you would implement inside the ECS or 
EKS environment  and for each one, explain what attack or mistake it prevents. 
Do not list generic items like “use HTTPS.” We want environment-specific controls: IAM task roles 
scoped to least privilege, VPC network segmentation between services, image scanning in the 
pipeline, secrets injection. For each control, complete this sentence: “Without this, an attacker (or a 
misconfigured service) could...

  Control 1: IAM Task Roles Scoped to Least Privilege  
Each service gets its own IAM role with only the permissions it needs  transcoding task can only touch the video S3 bucket, API task can only read its own secret.

Without this: a compromised transcoding container could call secretsmanager:ListSecrets, enumerate every secret in the account, and exfiltrate DB credentials for every service. One compromised task = entire AWS account compromised.

  Control 2: Security Group Segmentation Between Services  
Recommendation service SG: inbound 8080 from API service SG only. RDS SG: inbound 5432 from app SGs only. No 0.0.0.0/0 ingress except ALB on 443.

Without this: a compromised API container can directly probe the AI pipeline's internal port, attempt to poison recommendation data, or scan internal subnets. SGs enforce service-to-service boundaries at the network layer even if app-level auth is bypassed.

  Control 3: Container Image Scanning with Hard Gate in CI/CD  
Every image is scanned by Trivy before reaching ECR. Pipeline fails and does not push on any HIGH or CRITICAL CVE. ECR image scanning also runs continuously post-push.

Without this: a developer pulls node:20 in January, ships to prod in March  three critical CVEs published in between, nobody notices because the image is already in ECR. Attacker exploits one of them, gets RCE inside the ECS task with access to the task role credentials.

Q10.Write a CloudFormation or Terraform template that provisions a 
production-ready environment for this platform
ans.
Availble in the q10 folder

Q11. Write a Dockerfile for the React frontend. The final image must be under 150MB 
and must not run as root.

ans. It's available in q11 folder


Q12. After you submit your CloudFormation or Terraform template, your colleague 
points out that the ECS task role you wrote gives the service read access to every 
secret in the account. Fix it.

ans.

  Before (broken):  
json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": " "
}


  After (fixed):  
json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:vidstream-prod/db-password- "
}


The   resource means the task can read every secret in the account. The fixed version scopes it to the exact secret ARN (trailing handles the random suffix AWS appends).

  Catch this automatically in CI/CD:  
bash
#In GitHub Actions, before terraform apply:
pip install checkov
checkov -d ./terraform --framework terraform \
  --check CKV_AWS_46,CKV_AWS_107,CKV_AWS_108 \
  --hard-fail-on HIGH


CKV_AWS_46 catches wildcard actions, CKV_AWS_107/108 flag wildcard resource ARNs. --hard-fail-on HIGH makes the pipeline exit non-zero, blocking the merge before it ever reaches prod.



Q13.Write a GitHub Actions or Jenkins pipeline that deploys to Development and 
Staging environments. 

ans. q13 folder


Q14. Write a script (Bash or Python/Boto3) that scales ECS tasks to 0 at 8 PM and 
back to 2 at 8 AM, and also stops/starts the RDS instance on the same schedule.

ans. q14 folder


Q15. It is 11 PM. The on-call alert fires: the video upload service is throwing 500 
errors. You cannot SSH in because it is Fargate. Walk us through your first five 
minutes. 

ans.
First five minutes

The alert fired. First thing I do is not panic and start randomly clicking
around the console. I open two things simultaneously: the ALB metrics in
CloudWatch to confirm the 500s are real and get a sense of scale, and the
ECS service events page to see if there's an obvious deployment or task
crash staring me in the face.

Minute 0-1 — confirm scope

bash
#How bad is it and when did it start?
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=<alb-arn-suffix> \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time   $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum \
  --output table


This tells me: is it a spike that started at a specific minute (suggests
a deployment, config change, or external event) or has it been slowly
climbing (suggests resource exhaustion or a connection leak). The shape
of the graph matters before I go hunting in logs.

Minute 1-3 — get the actual error

Can't SSH, so CloudWatch Logs is the only window into the container.
I go straight to Logs Insights because grepping 30 minutes of log streams
manually is too slow at 11 PM:


#CloudWatch Logs Insights — run against /ecs/vidstream-prod/api
fields @timestamp, @message, @logStream
| filter @message like /ERROR|Exception|500|error/
| filter @message not like /healthcheck/
| sort @timestamp desc
| limit 50


I also run the CLI version in parallel because sometimes the console
is slow to load when you're stressed:

bash
aws logs tail /ecs/vidstream-prod/api \
  --since 15m \
  --filter-pattern "ERROR" \
  --format short


The '--since 15m' flag is important — I want logs from around when
the alert fired, not the last hour. The '--filter-pattern' cuts out
the noise immediately.

Minute 3-4 — check ECS task health

If the logs show crashes, I want to know if tasks are actually dying
and restarting (which creates a different kind of problem — new tasks
connecting to a potentially broken DB repeatedly):

bash
aws ecs describe-services \
  --cluster vidstream-cluster \
  --services vidstream-prod-api \
  --query 'services[0].{running:runningCount,pending:pendingCount,desired:desiredCount,deployments:deployments[*].{status:status,failed:failedTasks,running:runningCount}}' \
  --output table


If 'runningCount' is below 'desiredCount' and 'pendingCount' is
non-zero, tasks are crashing and restarting. That changes what I do next.

Minute 4-5 — check the immediate suspects

By this point I usually have enough from the logs to have a theory.
While I'm reading, I run these in the background:

bash
#RDS — is the database actually up?
aws rds describe-db-instances \
  --db-instance-identifier vidstream-prod-postgres \
  --query 'DBInstances[0].{status:DBInstanceStatus,connections:Endpoint}' \
  --output table

#RDS connection count — is it at the ceiling?
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=vidstream-prod-postgres \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time   $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average Maximum \
  --output table


By minute 5 I have: what the error message actually says, whether
tasks are crashing or just returning errors, and what RDS looks like.
That's enough to form a hypothesis and start ruling things out.

If logs show a database connection error

There are exactly three things I check, in this order, because they
go from "takes 30 seconds to rule out" to "takes a few minutes".

Three database failure modes, in order of how fast I can rule them out
Database connection error three causes:

Cause	How to rule out
RDS connection pool exhausted	Check DatabaseConnections CloudWatch metric → if near limit, increase max_connections
RDS security group changed	Compare current SG to last known working (GitHub commit)
RDS running out of storage	FreeStorageSpace < 1GB → extend storage or delete old records
Proactive dashboard: CloudWatch dashboard with:

ECS service CPUUtilization and MemoryUtilization

RDS DatabaseConnections and FreeStorageSpace

ALB 5xx count per target group

SQS ApproximateAgeOfOldestMessage


Q16. Your AWS bill has increased by 40% month-over-month with no new features 
shipped. Walk us through how you identify the source, fix it, and build guardrails so it 
cannot happen silently again.

ans.  Step 1  Cost Explorer:   Group by Service, compare this month vs last. Find the service with the largest dollar delta.

  Drill down:   Switch Group By to Usage Type within that service. For S3: DataTransfer-Out-Bytes spiking means videos served from S3 origin instead of CloudFront. For Fargate: group by Tag → Environment  if dev/staging tripled, tasks are running 24/7 when they should scale to 0.

  Top 3 cost reductions for video streaming specifically:  

 S3 Intelligent-Tiering Videos older than 30 days with low view counts auto-move to Infrequent Access. 80% of views happen in the first week; the savings on the long tail pay for the monitoring fee within 2 months.

 CloudFront cache hit ratio Check CacheHitRate metric. If it's low, TTLs are too short or cache keys include unnecessary headers (e.g. User-Agent). Fix cache behaviors to serve HLS segments with 24h TTL minimum. Directly reduces S3 GET costs and egress charges.

 Right-size Fargate tasks Container Insights shows actual CPU/memory utilisation per task over 2 weeks. Teams routinely over-provision 2x. Cutting a task from 2vCPU/4GB to 1vCPU/2GB halves Fargate cost for that service with zero user impact if utilisation data supports it.

  Wire into CI/CD so it can't happen silently again:  

Set Cost Anomaly Detection on the platform's cost allocation tag, threshold 15% week-over-week → SNS → Lambda → Slack #infra-costs. Then add infracost to GitHub Actions:

yaml
-uses: infracost/actions/setup@v2
-run: infracost diff --path=. --format=json > /tmp/cost.json
-run: infracost comment github --path=/tmp/cost.json --github-token=${{ secrets.GITHUB_TOKEN }}


Every Terraform PR gets an automatic comment showing monthly cost delta. Engineers see cost impact before code merges, not when the invoice arrives.
