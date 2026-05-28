# Where secrets live and how they get into the pipeline

## GitHub Secrets (repo Settings → Secrets and variables → Actions)

| Secret name          | What it is                                          | Why it's a secret               |
|----------------------|-----------------------------------------------------|---------------------------------|
| `AWS_DEPLOY_ROLE_ARN`| IAM role ARN the pipeline assumes via OIDC          | Masked in logs, hidden in forks |
| `DEV_URL`            | Internal ALB DNS for the dev environment            | Don't expose internal hostnames |
| `STAGING_URL`        | Internal ALB DNS for staging                        | Same reason                     |
| `SLACK_WEBHOOK_URL`  | Slack incoming webhook for deploy notifications     | Anyone with it can post to ops channel |

## What is NOT in secrets

There are no AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY anywhere.
We use OIDC. Here's the one-time AWS setup:

```bash
# 1. Create OIDC Identity Provider in IAM (do this once per account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --client-id-list sts.amazonaws.com

# 2. IAM role trust policy — scoped to THIS repo only
# Replace YOUR_GITHUB_ORG/YOUR_REPO with actual values
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
      }
    }
  }]
}
```

The `sub` condition is the important bit — it locks the role to your
specific repo. Without it, any GitHub Actions workflow anywhere could
assume the role if they got the ARN.

## GitHub Environment setup

Two environments need to exist in repo Settings → Environments:

**development** — no required reviewers, no wait timer. Deploys go straight through.

**staging** — add at least one required reviewer (usually the team lead
or whoever is on-call). When deploy-dev finishes, GitHub pauses the
pipeline and sends a review request. The reviewer sees the commit SHA,
can check the dev smoke test passed, and clicks Approve or Reject.
