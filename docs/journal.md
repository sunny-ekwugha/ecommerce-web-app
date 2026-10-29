# Ecommerce App on AWS with Terraform: Project Documentation

Production-like deployment of the four-service ecommerce app (product, cart, user, order) on AWS, built with Terraform from the IDE Kiro on Windows (Git Bash).

| Document | What it holds |
|---|---|
| [`README.md`](README.md) (this file) | Current status, what exists in AWS, open items, standing rules |
| [`runbook.md`](runbook.md) | Every command, in the order to run it, with what it does, what to expect, and whether it changes AWS |
| [`troubleshooting.md`](troubleshooting.md) | Every problem hit so far: symptom, cause, fix, how to prevent it |
| [`decision-log.md`](decision-log.md) | Every design decision with its reason, plus known risks and findings about the app code |

## Conventions used in all four documents

- **Placeholders, never real values.** Account ID, e-mail and the state bucket name are written as `<ACCOUNT_ID>`, `<BUDGET_EMAIL>` and `tfstate-<ACCOUNT_ID>-us-east-1`. The real values live only in two gitignored files: `terraform/envs/prod/backend.hcl` and `terraform/envs/prod/terraform.tfvars`. Resource IDs that Terraform can print (CloudFront domain, user pool ID, table ARNs) are not written down here, because they go stale. Run `terraform output` instead.
- **Status markers.**
  - ✅ ran, and the output was seen and checked
  - ◐ ran, but the output was not seen (the person reported success, or only part of the output was shared)
  - 📝 code written and planned, **not applied**
  - ⏳ not started yet
- **Cost markers.** 💲 creates something that bills while it exists. Prices quoted in these documents are rough figures from memory. Check the AWS pricing pages before relying on them.
- **Shell.** All commands are for Git Bash on Windows, run one line at a time (see `troubleshooting.md` entry S-1 for why).

## Where things stand (as of 2026-10-28)

**Summary.** The whole stack has been built, tested in a browser and torn down again from Terraform. Right now only the cheap or free layer exists in AWS (identity, data, hosting, registry, state bucket, budget); the paid layer (network, security groups, database, load balancer, ECS, API Gateway, SSM parameters) is destroyed and rebuilds from the saved code in one session. The tables below were written before the paid session; the session log at the end records what actually happened.

Repository: fork `sunny-ekwugha/ecommerce-web-app`, branch `terraform-prod`. Region `us-east-1`. Terraform `1.16.6` (pinned), AWS provider `6.69.1`.

### Built and running in AWS (cheap or free at idle)

| Piece | Terraform module | Status | Notes |
|---|---|---|---|
| State bucket | created by hand (bootstrap) | ✅ | Private, versioned, AES256, public access blocked, HTTPS-only policy |
| User pool and web client | `cognito` | ✅ | 2 resources. SRP and refresh flows only. MFA optional |
| Frontend hosting | `frontend` | ✅ | 29 resources. Private S3, CloudFront with origin access control, 20 product images |
| ECR repositories | `ecr` | ✅ | 8 resources. Immutable tags, scan on push |
| Container images | `scripts/build-and-push.sh` | ✅ | 4 images in ECR tagged `64d6332f100d` (rebuilt 2026-10-23 with `--pull`; verified in ECR). The older `89b8b8da0ee6` images remain until the lifecycle policy removes them |
| KMS key and DynamoDB tables | `data` | ◐ | 4 resources. Seeding worked, which proves the tables exist. The describe-table checks were not pasted |
| Product catalog | `catalog` | ✅ | 20 items. Item count and one image URL verified |
| Order-events topic | `messaging` | ✅ | 1 SNS topic, encrypted with the KMS key |
| IAM roles | `iam` | ✅ | 13 resources. One execution role and four task roles |
| Cost alert | `budget` | ✅ | $10 monthly budget, four e-mail alerts |

### Written and planned, not applied 📝

These cost money while they exist, so they are applied only in one deliberate session and destroyed the same day.

| Piece | Module | Plan result | Commit |
|---|---|---|---|
| Network (VPC, subnets, one NAT, endpoints, flow logs) | `network` | 26 to add | `7a68586` (was applied once, then destroyed) |
| Security groups | `security` | 14 in a targeted plan (13 ours plus the VPC) | `4bf5f51` |
| PostgreSQL database | `database` | 10 in a targeted plan | `fc39ab0` |
| Internal load balancer | `alb` | 14 in a targeted plan | `cfc009b` |
| ECS cluster and four services | `ecs` | 28 in a targeted plan | `a702db9` |
| API Gateway (HTTP API, VPC link, JWT authorizer, 9 routes) | `api` | 23 in a targeted plan (16 ours plus 7 dependencies: VPC, 2 ECS subnets, 2 security groups, ALB and listener). Reviewed 2026-10-22 | `be88453` |
| SSM parameters (7 under `/ecommerce/prod/`) | `ssm` | 21 in a targeted plan (7 ours plus 14 dependencies). Reviewed 2026-10-23 | `6becc1f` |

## Open items

| # | Item | What to do |
|---|---|---|
| O-1 | API Gateway module | ✅ Done: plan reviewed (23 to add) and committed as `be88453`. Waits for the paid session |
| O-2 | SSM parameters module | ✅ Done: written, planned (21 to add, reviewed) and committed (`6becc1f`, with the database retention fix in `310cd44`). Waits for the paid session. Without these parameters the services silently fall back to localhost settings (finding F-4) |
| O-3 | Image tag does not match any commit | ✅ Closed 2026-10-23: images rebuilt as `64d6332f100d` with `--pull`, verified in ECR, `image_tag` updated, ECS plan re-checked (28 to add) |
| O-4 | Image vulnerabilities | All four images show 3 HIGH, 9 MEDIUM, 3 LOW, identical across services, so they come from the shared base image. **Rebuilt with `--pull` on 2026-10-23 (tag `64d6332f100d`): the counts did not change (3 / 9 / 3 on all four).** So the newest `python:3.11-slim` still carries them. The three HIGH CVEs were looked up on the Debian security tracker (2026-10-24): two in glibc (marked minor, "no-dsa") and one in zlib; no fixed package exists for Debian 13 or 12, so a newer Debian-based base image would not remove them. **Proposed decision D28: accept for now and re-check at every rebuild. Waiting for the user's agreement** |
| O-5 | Frontend configuration | ✅ Scripted: `scripts/configure-frontend.sh` (`001eca3`) and `scripts/deploy-frontend.sh` (`e21be38`). `aws-config.js` still holds IDs from the deleted manual build until the script runs in the paid session, after the API is applied |
| O-6 | Three old local changes | `data/products.json`, `frontend/react-app/package.json` and `frontend/react-app/src/aws-config.js` are modified and uncommitted by design. Decide later whether to restore them to the repo version |
| O-7 | Leftovers from the manual build | Four ECR repos `ecommerce/*`, a dangling CloudFront distribution, the VPC `ecomm-app` (10.10.0.0/16), the IAM role `ecommerce-ecs-task-role`, and a hand-made budget. **Decision 2026-10-27: first "delete them", then revised the same day to "leave what is left if it costs nothing" (the user's call).** Done one resource at a time with a read-only check before and after each; Terraform's own resources are never touched (names `ecommerce-prod*`, VPC `10.20.0.0/16`). `ecsTaskExecutionRole` is a standard AWS role and stays. Status after the 2026-10-27 inventory: the old VPC `ecomm-app` and the old CloudFront distribution **no longer exist** (only the account's default VPC `172.31.0.0/16` and our own distribution remain), so the list written from memory was out of date. The old budget `mothly-cost-budget` ($20) still exists and **the user chose to keep it** (2026-10-27); it is not to be deleted. The wider sweep the same day found only our own resources in ECR (the four `ecommerce-prod/*` repos; the old `ecommerce/*` repos are gone), Cognito (`ecommerce-prod-users`), S3 (frontend and state buckets), DynamoDB (`ecommerce-prod-cart`, `ecommerce-prod-products`), and nothing in API Gateway, ECS or RDS. **The only leftover found is the IAM role `ecommerce-ecs-task-role`** (plus the kept budget). The remaining leftover (IAM role `ecommerce-ecs-task-role`, which carries no charge) and the old budget are **left in place on purpose**. The wider sweep of log groups, SSM, SNS, SQS, Lambda and Secrets Manager was not run; instead a cost-only baseline check (load balancers, NAT gateways, Elastic IPs, secrets) is done before the paid session. No deletion was run. Note for later: that role has broad permissions and should be removed before any real production use. List commands are in `runbook.md` section 9 |
| O-8 | `git push` | ✅ Pushed 2026-10-24: 14 commits, branch level with `origin/terraform-prod`. Push again after every future commit batch, after the pre-push check in runbook 4.4 |
| O-9 | The paid session | ✅ First session done 2026-10-28 (nine stages, tests passed, teardown of 91 resources, billing check empty). Repeat it with `runbook.md` section 8 whenever the stack is needed |
| O-10 | Before calling it production | WAF, custom domain and certificate, `single_nat_gateway = false`, Multi-AZ database, 2+ tasks per service, CI/CD with OIDC, Checkov scan, app-code fixes (finding F-1 to F-3), load balancer access logs and HTTPS, frontend: `npm audit` findings (43 on 2026-10-28, 1 critical) and not publishing source maps (`GENERATE_SOURCEMAP=false`) |
| O-11 | Large product image | `prod-007.jpg` is 2.5 MB. Resize the large images before the final deploy |

## Standing rules

1. **Never `apply` a plan you have not read.** Apply only the saved plan file: `terraform apply tfplan`.
2. **After every failed `plan`, delete the stale file first:** `rm -f tfplan`. `terraform show tfplan` displays whatever is in the file, even an old plan.
3. **Add files to git by explicit path.** Never `git add .` or `git add -A`. Three old modified files must stay out of commits.
4. **Check the staged list before committing.** Use `git diff --cached --name-only`, and commit only if the count is what you expect.
5. **Run Terraform only from `terraform/envs/prod`.** Never from inside `terraform/modules/*`.
6. **Destroy the paid stack at the end of every session** and run the three billing checks (runbook section 8).
7. **Any setting that comes from `terraform.tfvars` is read back in the plan.** The local override was missed four times (troubleshooting entries T-9 to T-12).
8. **Never filter warnings out of a command you use to check a setting.**
9. **Never commit** `terraform.tfvars`, `backend.hcl`, `*.tfplan`, `.terraform/`, state files or `plan.json`.
10. **Commit `.terraform.lock.hcl`.**
11. **Kiro's AI may explain things and write code, but never runs `apply` or `destroy`.**

## Session log

Newest last. Each entry says what changed in the project and which documents were updated.

| Date | What happened | Documents updated |
|---|---|---|
| 2026-10-22 | Documentation set rebuilt after the earlier journal copy was lost (it had stopped at step 34) | all four |
| 2026-10-22 | `plan -target=module.api` reviewed: 23 to add (9 routes, 2 integrations, authorizer, VPC link, stage with access logs, log group, plus 7 dependencies). Matches the design. Found that the authorizer needs the Cognito **ID token** (decision D24) | README, runbook 6.2 and 6.4, decision-log D24 |
| 2026-10-22 | API module committed as `be88453` | README (status, O-1, this log), runbook (6.2, commit table) |
| 2026-10-23 | SSM parameter names confirmed from the four `config.py` files: 7 names, matching the IAM paths. Still to confirm before writing the module: the `environment` value, whether the password is read with decryption, how the service URLs are used, and the database user and name | runbook 6.1, this log |
| 2026-10-23 | From `config.py`: password is read with decryption (fine); `environment` defaults to `local` and then SSM is skipped; defaults are `db_name=ecommercedb`, `db_user=postgres`. Still to check: what the ecs and database modules set, and how the order service builds URLs from the three service URL values | runbook 6.1, this log |
| 2026-10-23 | Confirmed: ecs module sets `ENVIRONMENT=var.env` and `AWS_REGION`; database user is `postgres`; order service appends its own paths, so URL parameters are the bare ALB base URL. Still to check: the `env` value passed from the root, the `db_name` default, and that ALB rules match plain `/cart` | runbook 6.1, this log |
| 2026-10-23 | Confirmed: ALB patterns `/products*`, `/cart*`, `/users*`, `/orders*` cover every path the order service calls. Root passes `env = var.env` and does not pass `db_name`. Two defaults still to read: `var.env` (root) and `db_name` (database module) | runbook 6.1, this log |
| 2026-10-23 | Both defaults confirmed (`env` = `prod`, `db_name` = `ecommercedb`). All SSM assumptions verified against the code; next step is writing the `ssm` module | runbook 6.1, this log |
| 2026-10-23 | `ssm` module code written and given (7 parameters, decision D27). Waiting for the user to create the files and paste the plan | decision-log D27, this log |
| 2026-10-23 | Fixes verified in the re-run plan: `backup_retention_period = 1`, log groups 14 days, plain SSM values visible (`insecure_value`; region and topic ARN show real values, the rest "known after apply"). Still 21 to add, 0 to change, 0 to destroy. Ready to commit as two commits (troubleshooting T-19, T-20) | troubleshooting T-19 and T-20, this log |
| 2026-10-23 | Committed: `6becc1f` (ssm module) and `310cd44` (database retention fix). All Terraform modules are now written, planned and committed. Next: image rebuild (O-3) | runbook (commit table), README (O-2) |
| 2026-10-23 | `--pull` added to the build script (`64d6332`). Images rebuilt by the script; it reported the tag `64d6332f100d`, which is the first 12 characters of a commit that is on the branch. Still to do: verify the four images in ECR, set `image_tag` in `terraform.tfvars`, re-plan ECS | this log |
| 2026-10-23 | All four images verified in ECR with tag `64d6332f100d` (pushed 17:20 to 17:24). Next: update `image_tag`, re-plan ECS, compare the vulnerability scan with the old images (O-4) | this log |
| 2026-10-23 | `image_tag` set in `terraform.tfvars` (local only, nothing to commit). ECS re-plan verified from the saved plan: 28 to add, 0 to change, 0 to destroy; all four images end in `:64d6332f100d`; every task definition has `ENVIRONMENT=prod` and `AWS_REGION=us-east-1`. O-3 closed. The vulnerability-scan comparison (O-4) has not been run yet | README (O-3) |
| 2026-10-23 | Frontend code checked: `api.js` sends the Cognito **ID token** (so the JWT authorizer will accept it) and `aws-config.js` is imported by `api.js` and `index.js`. Wrote `scripts/configure-frontend.sh` (reads three Terraform outputs, validates them, writes `aws-config.js`); tested against a stub with three cases (missing API, bad URL, good URL with trailing slash). To be created and committed by the user. The build-and-upload script comes next (O-5) | runbook 6.3, this log |
| 2026-10-23 | `scripts/configure-frontend.sh` run for real: it stopped with the expected "api_endpoint is empty or missing" error and left `aws-config.js` untouched. Committed as `001eca3`. The image tag `64d6332f100d` is still on the branch history (the commit is an ancestor of HEAD) | runbook (commit table), this log |
| 2026-10-23 | Wrote `scripts/deploy-frontend.sh` (configure, build, upload without ever deleting product images, verify the image count, invalidate `/index.html`; `--dry-run` supported). Tested against stand-ins for four cases. Build tool is `react-scripts`, so the output folder is `build`. Given to the user to create; not run against real AWS yet | runbook 6.3, this log |
| 2026-10-23 | `deploy-frontend.sh` committed as `e21be38` (syntax check passed, no CRLF). O-5 is now fully scripted; it can only be run in the paid session. Remaining before the paid session: O-4 scan comparison, O-7 leftovers decision, O-8 push, O-11 image sizes | runbook (commit table), this log |
| 2026-10-23 | Pre-push secret check on `terraform` and `scripts`: the account ID and the e-mail are in neither the current tree nor any commit. The only `[0-9]{12}` hit is hash noise in `.terraform.lock.hcl`. Next: repeat the history check over the whole repository, then push | runbook 4.4, this log |
| 2026-10-24 | Whole-repository history check: account ID in no commit; the budget e-mail in no commit. A generic `@gmail.com` search matched two commits (`db69da5`, `21d6845`) that belong to the original project and are already in `origin/main`, so they were a false alarm. Pushed 14 commits; `git status -sb` shows the branch level with `origin/terraform-prod`. O-8 closed | README (O-8), runbook 4.4, troubleshooting G-6 |
| 2026-10-24 | Vulnerability scan of the rebuilt images (status COMPLETE on all four): 3 HIGH, 9 MEDIUM, 3 LOW each, identical to the old images. `--pull` did not reduce the findings. Open question: are fixes available upstream at all | README (O-4), this log |
| 2026-10-24 | HIGH CVEs identified and checked against the Debian tracker: CVE-2026-19499 and CVE-2026-5435 (glibc, "no-dsa", fixed only in forky/sid) and CVE-2026-85091 (zlib, no fix yet). Decision D28 proposed (accept, re-check each rebuild) | decision-log D28, README (O-4) |
| 2026-10-27 | Full untargeted dress-rehearsal plan: **91 to add, 0 to change, 0 to destroy**. The already-built modules show no drift. Not applied (it creates everything that bills). The user decided to delete the leftovers from the manual build (O-7); inventory first | runbook 8.1, README (O-7) |
| 2026-10-27 | Leftovers decision: old IAM role and old budget stay (free). Sweep of ECR, Cognito, S3, DynamoDB, API Gateway, ECS, RDS found only our own resources. Billing baseline before the first paid session: load balancers, NAT, Elastic IPs, secrets, RDS, ECS all empty. O-7 closed | README (O-7), runbook 8.4 |
| 2026-10-27 | Readiness checks done: every service has `/health`; user and order services create their tables at startup; connection code sets no `sslmode`. Runbook 8.2 rewritten (corrected order: ssm after alb; per-stage checks and failure rules). The user chose to start the paid session the next day. **Next session starts at stage 1 (network), after the start-of-session routine in runbook 4.1 and a check of how the AWS login is set up and how long it lasts** | runbook 8.2, decision-log F-5 |
| 2026-10-28 | **Paid session started.** Start-of-session checks passed (clean repo, long-lived IAM keys for user `admin`, clean billing baseline). Stage 1 (network): plan `26 to add` (24 listed resources plus the flow-log log group and the default security group at the top of the list), applied; checks passed (one VPC `10.20.0.0/16`, one NAT gateway available, drift check "No changes"). **NAT gateway billing started.** | runbook 8.2 |
| 2026-10-28 | Stage 2 (security): 13 added, 4 security groups present, drift check clean. Stage 3 (database): 6 added; instance `available`, single-AZ, `db.t4g.micro`, backups 1 day. The drift check showed one in-place change (the `rds.force_ssl` apply method; the code never set it, AWS reports `pending-reboot`); fixed in code by adding `apply_method = "pending-reboot"`, drift check then clean (troubleshooting T-21). **RDS billing started.** | troubleshooting T-21, this log |
| 2026-10-28 | Code fix committed as `607de92` (apply method). Stage 4 (alb): plan 10 to add, settings read back (internal, port 80, 4 target groups on 8001 to 8004 checking `/health` expecting 200, rules `/products*` 10, `/cart*` 20, `/users*` 30, `/orders*` 40), applied; load balancer `active`, 4 target groups, drift clean. **Load balancer billing started.** Stage 5 (ssm): 7 to add (values read back: three identical bare ALB URLs, DB host, topic ARN, region), applied; 6 `String` plus `db/password` as `SecureString`, drift clean | runbook 8.2, this log |
| 2026-10-28 | Stage 6 (ecs): plan 13 to add (cluster, 4 task definitions, 4 services, 4 log groups; Fargate, 1 task each, 256 CPU / 512 MB, no public IP, images `:64d6332f100d`). The health check grace period was raised from 60 to 120 seconds before the apply (a guess that the services need more than 60 s to start on 0.25 vCPU; to be changed only on evidence). Applied: 13 added. **All four services `running 1` and all four targets `healthy`** within about three minutes, first try, so the SSM settings, database connection and table creation work. **Fargate billing started.** | runbook 8.2, this log |
| 2026-10-28 | Stage 7 (api): plan 16 to add (same list as the 2026-10-22 review), applied. First end-to-end tests from the user's computer: `GET /products` returned 200 with real catalogue JSON (image URLs on the CloudFront domain); `GET /cart` with no token returned **401** (the authorizer guards the services, F-1 mitigated at the gateway); `PUT /products/prod-001/inventory` returned **404** (internal route not exposed); drift check clean. Next: frontend deploy (dry run first), browser tests, full drift check, teardown | runbook 8.2, 6.4, decision-log F-1 |
| 2026-10-28 | Stage 8 dry run of `deploy-frontend.sh`: first attempt stopped at `npm ci` (a stale local git-ignored lock file, out of sync with `package.json`; troubleshooting N-1); after `npm install` it built successfully (`react-scripts`, two harmless ESLint hook warnings), listed only uploads (static assets and root files), **no delete lines, nothing under `images/`**, product images 20 before and 20 after. `npm ci` took about 10 minutes (project is in a OneDrive folder). Noted for later: `npm audit` reports 43 vulnerabilities (1 critical, 18 high) in the frontend toolchain; source maps (`*.map`) are uploaded to the public site (set `GENERATE_SOURCEMAP=false` for production). Added to O-10 | troubleshooting N-1, README (O-10) |
| 2026-10-28 | Stage 8 real deploy with `SKIP_INSTALL=1` (an option added to the script that day): 17 files uploaded, product images 20 before and 20 after, CloudFront invalidation of `/index.html` created (`InProgress`), site at the CloudFront domain. The script change is still to be committed. Next: browser tests (runbook 6.4) | runbook 6.3, this log |
| 2026-10-28 | Browser tests: the user reported that the deployed site works ("it works fine") end to end in the browser. The individual steps (sign-up, login, cart, order, deep-link refresh, console) were not itemised by the user, so this entry records the overall result only. Next: full drift check, then teardown of the paid modules | runbook 6.4, 8.3 |
| 2026-10-28 | **Teardown done.** Destroy plan `0 to add, 0 to change, 91 to destroy` with the per-module split alb 10, api 16, database 6, ecs 13, network 26, security 13, ssm 7 and no other module; applied (reported "destroy complete"). Six-section billing check afterwards: load balancers, NAT, Elastic IPs, secrets, RDS, ECS all empty, same as the morning baseline. Still to confirm: the post-destroy plan should show `91 to add, 0 to change, 0 to destroy`, and the pre-destroy full drift check result was not shown to me | runbook 8, 8.3, 8.4 |
| 2026-10-28 | Post-destroy plan: **`Plan: 91 to add, 0 to change, 0 to destroy`**, no destroy or update lines, so only the paid pieces were removed and everything else matches the code. Pushed `e21be38..644839b` to `origin/terraform-prod` (the user ran a plain `git push`; the safety check was run just afterwards and passed: neither the account ID nor the budget e-mail is in any commit, `Everything up-to-date` followed). Lesson: run the check before the push, not after | runbook 4.4, this log |
| 2026-10-23 | `plan -target=module.ssm` reviewed: 21 to add (7 ssm plus 14 dependencies), no change or destroy, the 7 names are right. Three follow-ups before commit: (1) `backup_retention_period = 14` in the database, but the design says 1 day, so check which variable it reads; (2) plain parameter values are hidden as "sensitive" in the plan, so switch them to `insecure_value`; (3) check the KMS key policy lets CloudWatch Logs use the key, because the two database log groups are encrypted with it. Not committed yet | this log, decision-log (risks) |
| 2026-10-23 | Follow-up (3) checked: the KMS key policy has a statement for `logs.<region>.amazonaws.com` limited to log groups in this account, which is the documented pattern (the allowed actions were not in the grep, so the apply is the final proof). Follow-up (1) found: in `database/main.tf` line 32 (a log group) reads `var.backup_retention_days` and line 65 (`backup_retention_period`) reads `var.log_retention_days`. The two variables are swapped, a leftover of the T-8 fix. Waiting for the variable defaults to confirm the values | this log |
