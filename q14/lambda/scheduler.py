"""
ECS + RDS cost scheduler — Dev and Staging only
================================================
Scales ECS desired count to 0 at 8 PM IST (14:30 UTC).
Scales back to 2 at 8 AM IST (02:30 UTC).
Stops RDS on the same evening schedule, starts it in the morning.

Deployed as a Lambda function triggered by two EventBridge rules.
EventBridge passes {"action": "scale-down"} or {"action": "scale-up"}
in the event payload so one function handles both directions.

Why Python over Bash:
Bash is fine for one-liners but error handling gets messy — you end up
checking $? after every command and parsing CLI output as strings.
Boto3 gives structured exceptions so I can handle "already stopped"
vs "instance not found" vs "actual API error" cleanly and separately.
"""

import boto3
import logging
import os
import sys
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# All config comes from Lambda environment variables, not hardcoded.
# Each environment (dev/staging) gets its own Lambda with its own
# env vars pointing at the right cluster/service/RDS instance.
ECS_CLUSTER    = os.environ["ECS_CLUSTER"]      # e.g. vidstream-dev-cluster
ECS_SERVICE    = os.environ["ECS_SERVICE"]       # e.g. vidstream-dev-api
RDS_IDENTIFIER = os.environ["RDS_IDENTIFIER"]    # e.g. vidstream-dev-postgres
SCALE_UP_COUNT = int(os.environ.get("SCALE_UP_COUNT", "2"))

ecs = boto3.client("ecs")
rds = boto3.client("rds")


# ─── ECS helpers ──────────────────────────────────────────────────────────────

def get_ecs_service():
    """
    Return the service description dict, or None if it doesn't exist.

    ECS returns an empty list (or a service with status=INACTIVE) when
    you describe a service that's been deleted. Both mean the same thing
    operationally — nothing to scale. Logging a warning here is enough;
    we don't want a missing dev service to page someone at 8 PM.
    """
    try:
        resp = ecs.describe_services(
            cluster=ECS_CLUSTER,
            services=[ECS_SERVICE]
        )
    except ClientError as e:
        # ClusterNotFoundException lands here too — the cluster itself is gone.
        logger.error(
            "describe_services failed — cluster may not exist. "
            "cluster=%s error=%s", ECS_CLUSTER, e
        )
        return None

    services = resp.get("services", [])
    if not services or services[0]["status"] == "INACTIVE":
        logger.warning(
            "ECS service not found or INACTIVE, skipping. "
            "cluster=%s service=%s", ECS_CLUSTER, ECS_SERVICE
        )
        return None

    return services[0]


def scale_ecs(desired_count: int):
    service = get_ecs_service()
    if service is None:
        return

    current = service["desiredCount"]
    if current == desired_count:
        logger.info(
            "ECS already at %d — nothing to do. service=%s",
            desired_count, ECS_SERVICE
        )
        return

    try:
        ecs.update_service(
            cluster=ECS_CLUSTER,
            service=ECS_SERVICE,
            desiredCount=desired_count
        )
        logger.info(
            "ECS scaled %d -> %d. service=%s", current, desired_count, ECS_SERVICE
        )
    except ClientError as e:
        # Re-raise so the Lambda invocation is marked failed in EventBridge.
        # That triggers the DLQ, which triggers an alarm. Real errors should
        # not pass silently.
        logger.error("update_service failed. service=%s error=%s", ECS_SERVICE, e)
        raise


# ─── RDS helpers ──────────────────────────────────────────────────────────────

def get_rds_status():
    """
    Return the DB instance status string, or None if not found.

    RDS instance statuses we care about:
      available  — running, safe to stop
      stopped    — already stopped, safe to start
      stopping   — mid-stop, don't try to stop again
      starting   — mid-start, don't try to start again
      backing-up — AWS is snapshotting it, can't stop during backup
      modifying  — a parameter change is applying

    Only 'available' and 'stopped' are safe to act on.
    Any other state: skip this run and let the next scheduled
    invocation handle it.
    """
    try:
        resp = rds.describe_db_instances(DBInstanceIdentifier=RDS_IDENTIFIER)
        status = resp["DBInstances"][0]["DBInstanceStatus"]
        logger.info("RDS status=%s identifier=%s", status, RDS_IDENTIFIER)
        return status
    except ClientError as e:
        if e.response["Error"]["Code"] == "DBInstanceNotFound":
            logger.warning("RDS instance not found, skipping. identifier=%s", RDS_IDENTIFIER)
            return None
        logger.error("describe_db_instances failed. error=%s", e)
        raise


def stop_rds():
    """
    Stop RDS for the evening.

    Most common edge case: the instance is already stopped because
    a previous run got it, or someone stopped it manually.
    RDS throws InvalidDBInstanceState if you call stop on a stopped
    instance — we catch that specifically and treat it as a no-op,
    not an error.
    """
    status = get_rds_status()
    if status is None:
        return

    if status == "stopped":
        # Already done. Could be a previous run, could be manual.
        # Either way this is the state we wanted — log and move on.
        logger.info("RDS already stopped, nothing to do. identifier=%s", RDS_IDENTIFIER)
        return

    if status != "available":
        # backing-up, stopping, modifying, etc.
        # Not safe to call stop right now. Skip and let next run handle it.
        logger.warning(
            "RDS in state '%s', cannot stop safely right now, skipping. "
            "identifier=%s", status, RDS_IDENTIFIER
        )
        return

    try:
        rds.stop_db_instance(DBInstanceIdentifier=RDS_IDENTIFIER)
        logger.info("RDS stop initiated. identifier=%s", RDS_IDENTIFIER)
    except ClientError as e:
        if e.response["Error"]["Code"] == "InvalidDBInstanceState":
            # Race condition: status changed between our describe call above
            # and this stop call (e.g. a backup started in that window).
            # Not a real problem — log it and continue.
            logger.warning(
                "RDS state changed between check and stop, skipping. "
                "identifier=%s error=%s", RDS_IDENTIFIER, e
            )
        else:
            logger.error("stop_db_instance failed. identifier=%s error=%s", RDS_IDENTIFIER, e)
            raise


def start_rds():
    """
    Start RDS in the morning.

    start_db_instance is async — it returns immediately but the instance
    takes ~3-5 minutes to reach 'available'. We call this before scaling
    ECS up so RDS has a head start warming up. The app should have
    connection retry logic to handle the gap if it's not ready yet.
    """
    status = get_rds_status()
    if status is None:
        return

    if status == "available":
        logger.info("RDS already running, nothing to do. identifier=%s", RDS_IDENTIFIER)
        return

    if status != "stopped":
        logger.warning(
            "RDS in state '%s', cannot start right now, skipping. "
            "identifier=%s", status, RDS_IDENTIFIER
        )
        return

    try:
        rds.start_db_instance(DBInstanceIdentifier=RDS_IDENTIFIER)
        logger.info("RDS start initiated. identifier=%s", RDS_IDENTIFIER)
    except ClientError as e:
        if e.response["Error"]["Code"] == "InvalidDBInstanceState":
            logger.warning(
                "RDS state changed before start could execute. "
                "identifier=%s error=%s", RDS_IDENTIFIER, e
            )
        else:
            logger.error("start_db_instance failed. identifier=%s error=%s", RDS_IDENTIFIER, e)
            raise


# ─── Lambda handler ────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    """
    EventBridge passes {"action": "scale-down"} or {"action": "scale-up"}.

    Order matters:
      scale-down: ECS first, then RDS.
        Stop tasks before stopping the DB. If you stop RDS first,
        running containers will hammer it with failed connection attempts
        and CloudWatch fills up with errors that look alarming even
        though they're intentional.

      scale-up: RDS first, then ECS.
        Give RDS a few minutes to warm up before tasks try to connect.
        App connection retry logic covers the remaining gap.
    """
    action = event.get("action")
    logger.info("Scheduler invoked. action=%s cluster=%s", action, ECS_CLUSTER)

    if action == "scale-down":
        logger.info("=== Evening scale-down (8 PM IST) ===")
        scale_ecs(desired_count=0)
        stop_rds()

    elif action == "scale-up":
        logger.info("=== Morning scale-up (8 AM IST) ===")
        start_rds()   # RDS first — needs time to warm up
        scale_ecs(desired_count=SCALE_UP_COUNT)

    else:
        # Misconfigured EventBridge rule, or someone tested with wrong payload
        logger.error("Unknown action '%s' in event payload", action)
        raise ValueError(f"Unknown action: '{action}'. Expected 'scale-down' or 'scale-up'.")

    logger.info("Done. action=%s", action)
    return {"status": "ok", "action": action}


# ─── Local testing ────────────────────────────────────────────────────────────
# Set env vars and pass an action:
#   ECS_CLUSTER=vidstream-dev-cluster \
#   ECS_SERVICE=vidstream-dev-api \
#   RDS_IDENTIFIER=vidstream-dev-postgres \
#   python scheduler.py scale-down
if __name__ == "__main__":
    import json
    action = sys.argv[1] if len(sys.argv) > 1 else "scale-down"
    result = lambda_handler({"action": action}, context=None)
    print(json.dumps(result, indent=2))
