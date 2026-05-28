#Q14 — Written Answer

#Schedule triggers

Two EventBridge cron rules, both UTC (EventBridge only speaks UTC):

'''
Scale down (8 PM IST):  cron(30 14 * * ? *)
Scale up   (8 AM IST):  cron(30 2  * * ? *)
'''

IST is UTC+5:30, so 8:00 PM IST = 14:30 UTC, 8:00 AM IST = 02:30 UTC.

The '?' in the day-of-month field is required by EventBridge cron syntax
when you're not specifying a particular day — it means "any day". Most
AWS docs don't explain this and it's a common trip-up when someone migrates
from standard Unix cron where '*' works fine in that position.



#Error handling decisions

RDS already stopped:
'describe_db_instances' runs first and we check the status before touching
anything. If status is 'stopped', we log it and return — no API call to stop
it again, no error. This covers the case where a previous run already did it
or someone stopped it manually between runs.

We also explicitly handle the race condition where the status check returns
'available' but by the time 'stop_db_instance' fires, AWS has already started
a scheduled backup and moved it to 'backing-up'. That call throws
'InvalidDBInstanceState'. We catch that specific error code and treat it as
a warning, not a failure.

ECS service doesn't exist:
'describe_services' returns an empty list (or a service with 'status=INACTIVE')
when the service is gone. We return 'None' from the helper and skip cleanly.
ECS also throws 'ClusterNotFoundException' if the whole cluster is missing —
that's caught in the same block. Neither of these should alert the on-call
engineer; they're expected states in dev/staging where infra sometimes gets
torn down.

Actual errors (permissions, API failures):
These get re-raised after logging. The Lambda invocation is marked as failed,
EventBridge retries it twice, then drops the event on the DLQ. There's a
CloudWatch alarm on the DLQ that fires if any message lands there. Real errors
surface; expected states don't noise up on-call.



#Two additional AWS-native cost controls

1. AWS Budgets with environment-level tag filters

Set a monthly budget on resources tagged 'Environment=dev' and a separate one
for 'Environment=staging'. Alert at 80% of the budget threshold via SNS → email
and Slack. The key thing here is tagging enforcement — if a resource doesn't
have the tag, it doesn't show up in the budget and can grow silently.

Use AWS Config rule 'required-tags' to flag any resource missing the
'Environment' tag. That way the budget coverage is actually complete.

I'd set the budget thresholds based on a known baseline (e.g. if dev normally
costs $150/month, set alert at $120). A 40% overage alert means you hear about
it mid-month, not when the invoice arrives.

2. S3 Lifecycle Policies + RDS automated snapshot cleanup

In dev/staging, video uploads and transcoded files accumulate in S3 without
anyone noticing. A lifecycle rule that transitions objects to S3-IA after 7 days
and deletes them after 30 days keeps storage costs flat regardless of how much
test data gets uploaded.

Same issue with RDS automated snapshots — AWS keeps them for the retention
period you set, but in dev you don't need 7 days of point-in-time recovery.
Set 'backup_retention_period = 1' on dev RDS. That's 6 fewer daily snapshots
sitting in storage.

Both of these are set-and-forget. You configure them once in Terraform and
they run forever without needing a script or a person to remember.
