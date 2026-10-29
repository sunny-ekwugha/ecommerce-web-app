# Troubleshooting

Every problem hit in this project, grouped by area. Each entry: **Symptom** (what you see), **Cause**, **Fix** (commands), **Prevent**.

| Prefix | Area |
|---|---|
| S | Shell and Git Bash |
| W | Windows tools (Chocolatey, Docker) |
| T | Terraform |
| G | Git |
| A | AWS |
| M | The original manual deployment (CORS, images) |
| N | npm and the frontend build |

Entries marked *(mine)* were wrong claims or mistakes by the assistant that were caught and corrected.

This file was rebuilt from a conversation summary. The causes in **S-6, T-5, G-4, M-1 and M-2** are reconstructed and less certain than the rest; the fixes in them are the ones that worked.

---

## S: Shell and Git Bash

### S-1 Pasted commands glued together
- **Symptom:** several commands run as one line, or one command errors with text from the next.
- **Cause:** Git Bash's bracketed-paste handling sometimes drops the line break between pasted lines.
- **Fix:** press Enter, then rerun the commands.
- **Prevent:** paste **one line at a time** and wait for the prompt.

### S-2 Output stops at a `:` prompt (git pager)
- **Symptom:** `git log` or `git diff` shows text then a `:` or `(END)` and seems stuck.
- **Cause:** git hands long output to a pager.
- **Fix:** press `q`.
- **Prevent:** `git --no-pager log --oneline -5`.

### S-3 `warning: LF will be replaced by CRLF`
- **Symptom:** printed by `git add`.
- **Cause:** Windows line-ending conversion. Harmless for now.
- **Fix:** none needed. Add a `.gitattributes` before starting CI work, and check shell scripts with `grep -c $'\r' scripts/build-and-push.sh` (want 0; fix with `sed -i 's/\r$//' <file>`).

### S-4 AWS command mangles a path or ARN
- **Symptom:** a value starting with `/` is rewritten into a Windows path such as `C:/Program Files/Git/...`.
- **Cause:** Git Bash path conversion.
- **Fix/Prevent:** `export MSYS_NO_PATHCONV=1` in that terminal first.

### S-5 Commands run in the wrong folder
- **Symptom:** `terraform init` finds no configuration; `cd` says no such directory; Terraform files or a state lock file appear under `modules/`.
- **Cause:** relative paths typed from a different starting folder.
- **Fix:** `cd "$(git rev-parse --show-toplevel)/terraform/envs/prod"`, then `pwd` to confirm.
- **Prevent:** always use the `git rev-parse` idiom (runbook section 0). Terraform runs only in `envs/prod`.

### S-6 `touch` of a script fails
- **Symptom:** error on `touch scripts/build-and-push.sh`.
- **Cause:** run from a folder where `scripts/` does not exist (the repo root is the one that has it).
- **Fix:** `cd "$(git rev-parse --show-toplevel)"` first, check `ls scripts`.

---

## W: Windows tools

### W-1 `docker info` says it cannot connect to the engine
- **Symptom:** `docker --version` works, but `docker info` shows a Client section and then an error about the pipe / daemon.
- **Cause:** Docker Desktop is not running. The CLI prints its version without the engine.
- **Fix:** start Docker Desktop, wait for the whale icon to settle, rerun `docker info`. Success shows a `Server:` section with `Server Version`.
- **Prevent:** run `docker info >/dev/null 2>&1 && echo "docker engine OK" || echo "docker engine NOT running"` before any build. An earlier version of this check filtered the output with `grep -E "Server Version|ERROR"`; on 2026-10-23 it appeared to print nothing, yet the engine was running (the full `docker info` output was normal). The cause was not found; the output may simply not have been pasted, and an earlier note here that blamed the Docker version's wording was a guess and has been withdrawn. The new check always prints one of two answers, so an empty result can no longer be mistaken for either state. *(mine)*

### W-2 Chocolatey installed a release candidate *(mine)*
- **Symptom:** `terraform -version` shows `v1.17.0-rc2`.
- **Cause:** the installed pre-release kept Chocolatey on the pre-release track. I had wrongly said choco ignores pre-releases.
- **Fix** (administrator PowerShell):
  ```powershell
  choco upgrade terraform --version=1.16.6 --allow-downgrade -y
  choco pin add --name=terraform --version=1.16.6
  choco pin list
  ```
  Expect `terraform|1.16.6`. Open a **new** Git Bash and run `terraform -version`.
- **Prevent:** keep the pin; change versions on purpose only.

### W-3 Old terminal still shows the old version
- **Cause:** a terminal keeps its PATH from when it was opened.
- **Fix:** close it and open a new Git Bash.

---

## T: Terraform

### T-1 `init` in the wrong folder
See S-5. Symptom was an init that found no configuration. Fix: go to `envs/prod`.

### T-2 `init` asks for "bucket"
- **Symptom:** prompt `bucket - The name of the S3 bucket`.
- **Cause:** the backend uses a partial configuration; the bucket name is not in `versions.tf` (decision D12).
- **Fix:** `terraform init -backend-config=backend.hcl`, with `backend.hcl` containing `bucket = "tfstate-<ACCOUNT_ID>-us-east-1"`.

### T-3 Files exist but are empty
- **Symptom:** `validate` reports missing things; `wc -l` shows `0`.
- **Cause:** seven of eight files were created with `touch` and never filled (or never saved).
- **Fix:** paste the contents, save, recheck with `wc -l ../../modules/<name>/*.tf`.
- **Prevent:** run `wc -l` before every `plan`; no file may show 0.

### T-4 `Module not installed`
- **Cause:** a new `module` block was added to `main.tf` without re-initialising.
- **Fix:** `terraform init -backend-config=backend.hcl`. Repeat after adding any module.

### T-5 Singular file names (`output.tf`, `variable.tf`)
- **Symptom:** variables or outputs "not declared".
- **Cause:** files named singular. Terraform reads any `.tf` file, so this is a convention issue first, but it caused mismatches and confusion.
- **Fix:** `mv output.tf outputs.tf` and `mv variable.tf variables.tf` (inside the module folder). Convention: `main.tf`, `variables.tf`, `outputs.tf`.

### T-6 Stray `.terraform.tfstate.lock.info` in a module folder
- **Cause:** a Terraform command was run from inside `modules/catalog`.
- **Fix:** delete the file (`rm terraform/modules/catalog/.terraform.tfstate.lock.info`), then run commands from `envs/prod`. It is gitignored, but check `ls -a` anyway.

### T-7 `terraform fmt -check` lists files
- **Fix:** `terraform fmt -recursive ../..`, then run `-check` again; it must print nothing.

### T-8 Database log group used the wrong retention value
- **Symptom:** plan showed log retention of 1 day instead of 14.
- **Cause:** the log-group resource referenced the backup-retention variable (also 1).
- **Fix:** use `var.log_retention_days` for the log group.
- **Prevent:** read each number in the plan against the variable it should come from.

### T-9 to T-12 `terraform.tfvars` overrides forgotten (four slips)
- **Symptom:** the plan shows production-locked settings although practice mode was intended (or the reverse).
- **Cause:** the module defaults were production-safe, so each destroy-related setting needed a matching line in `terraform.tfvars`, and one was missed each time.
  - T-9 Cognito: deletion protection `ACTIVE` instead of `INACTIVE`, and MFA setting.
  - T-10 Frontend bucket: `force_destroy` not true.
  - T-11 ECR: `force_delete` not true.
  - T-12 Data: `deletion_protection` not turned off.
- **Fix (permanent):** one switch, `allow_destroy`, in `variables.tf` (default `false` = production-locked), mapped inside each module:
  - cognito: `var.allow_destroy ? "INACTIVE" : "ACTIVE"`
  - frontend: `force_destroy = var.allow_destroy`
  - ecr: `force_delete = var.allow_destroy`
  - data: `deletion_protection = !var.allow_destroy`

  After the refactor the plan showed `No changes.` Committed as `b7077b6`.
- **Prevent:** read back every tfvars-driven setting in the plan (`terraform show tfplan | grep -E "force_delete|deletion_protection|force_destroy"`) and never filter warnings out of such a check (standing rule 8).

### T-13 `terraform show tfplan` shows an old plan
- **Symptom:** after a plan that failed, `show` still prints content.
- **Cause:** the failed plan did not overwrite `tfplan`.
- **Fix/Prevent:** `rm -f tfplan` before every plan.

### T-14 A plain `plan` lists the 26 network resources
- **Cause:** the network was destroyed after the first session; an untargeted plan wants to rebuild it and everything that depends on it.
- **Fix:** `terraform plan -target=module.<name> -out=tfplan`. Expect targeted plans to include dependencies (a "13 resource" module may show 14 to add, because the VPC comes with it).

### T-15 ECS `container_definitions` "known after apply" *(mine, design)*
- **Symptom:** plan could not show the task definitions' contents.
- **Cause:** `depends_on` on the whole `module "ecs"` block makes every value in the module unknown at plan time.
- **Fix:** remove the module-level `depends_on`; put the dependency on the ALB module output:
  ```hcl
  output "target_group_arns" {
    value      = { for k, tg in aws_lb_target_group.svc : k => tg.arn }
    depends_on = [aws_lb_listener_rule.svc]
  }
  ```
  Anything using `module.alb.target_group_arns` now waits for the listener rules. Committed in `a702db9`.

### T-16 `grep "^Plan:"` finds nothing
- **Cause:** colour codes in the output hide the line start.
- **Fix:** `terraform plan -no-color | grep -E "^Plan:"`.

### T-17 `.gitignore` wrong about the lock file and plan files
- **Symptom:** `.terraform.lock.hcl` was ignored; `destroy.tfplan` not ignored.
- **Fix:** delete the lock-file line; add `*.tfplan`. The lock file must be committed so everyone gets the same provider versions.

### T-18 Plan warning "Resource targeting is in effect"
Expected whenever `-target` is used. Any **other** warning needs an explanation before you apply.

### T-19 Database backup retention was 14 days, not 1 (T-8 fix was half-done)
- **Symptom:** the 2026-10-23 plan showed `backup_retention_period = 14`, but the design is 1 day to keep cost down.
- **Cause:** two things. (a) In `database/main.tf` the two retention variables were swapped: a log group read `var.backup_retention_days` and `backup_retention_period` read `var.log_retention_days`, so the T-8 fix had corrected only one line. (b) The `backup_retention_days` default in `variables.tf` was 14, not 1. Because both defaults were 14, the swap was invisible in the plan values and only the number gave it away.
- **Fix:** log group reads `var.log_retention_days`; `backup_retention_period` reads `var.backup_retention_days`; the `backup_retention_days` default becomes `1`.
- **Prevent:** when two variables have the same default, a swap cannot be seen in a plan. Give them different defaults, or check which variable each line reads (`grep -n "retention" terraform/modules/database/main.tf`).

### T-20 Plan shows `(sensitive value)` for ordinary SSM parameters
- **Symptom:** every `aws_ssm_parameter` value is hidden in the plan, including non-secret ones like the ALB URL.
- **Cause:** the provider marks `value` as sensitive for all parameter types.
- **Fix:** for `String` parameters use `insecure_value = each.value`. Keep `value` for the `SecureString`.
- **Prevent:** a hidden value cannot be reviewed and a changed value shows no diff.

### T-21 Drift check after the database apply shows `0 to add, 1 to change`
- **Symptom (2026-10-28):** right after a successful apply of `module.database`, `plan -target=module.database` shows the parameter group `rds.force_ssl` being replaced inside a `parameter` block: `apply_method = "pending-reboot" -> null` and then `+ apply_method = "immediate"`, with the same `name` and `value = "1"`.
- **Cause:** the code did not set `apply_method` at all, so the provider filled in its default, `immediate`, while AWS stores and reports `pending-reboot` for this parameter. Terraform therefore saw a difference on every plan. Only the apply method differs; the value `1` is the same. The database was created with this parameter group already attached, so the setting is in effect without a reboot.
- **Fix:** **add** the line `apply_method = "pending-reboot"` to the `rds.force_ssl` `parameter` block in `terraform/modules/database/main.tf` (the block had only `name` and `value`; found with `grep -n -B2 -A4 "rds.force_ssl"`). Do **not** apply the in-place change as it was planned: asking AWS for `immediate` on a parameter it treats as needing a reboot can be refused.
- **Prevent:** after every apply, run the drift check and read any non-empty result before moving on.

---

## G: Git

### G-1 A stray `.tf` file was committed in `messaging`
- **Symptom:** `git status` or `ls -a` shows a file named just `.tf`.
- **Fix:**
  ```bash
  git rm terraform/modules/messaging/.tf
  git commit --amend --no-edit
  ```
  (the amend rewrites the commit, see G-2).

### G-2 Amending changed the commit hash
- **Impact:** images were tagged with the pre-amend hash `89b8b8da0ee6`, which is no longer on the branch (open item O-3). Same for `db8f4dc` (now `219a7b8`).
- **Fix:** rebuild after the commit is final and update `image_tag`.
- **Prevent:** never amend after you have pushed an image tagged with that hash.

### G-3 `git check-ignore` prints nothing
- **Cause:** it was run with no path (it prints nothing), or the file is not ignored.
- **Fix:** `git check-ignore -v <path>`. One line per ignored file; nothing means not ignored.

### G-4 A module folder was not in the commit
- **Symptom:** "why is the budget folder not included?"
- **Cause:** the folder was never created on the user's machine; the assistant cannot create files there.
- **Fix:** create `terraform/modules/budget` with its three files, then `git status --short` to confirm they appear as `??` before adding by path.

### G-6 The guarded push printed nothing and pushed nothing
- **Symptom:** a push line made of `[ -z "$(git log ... )" ] && ... && git push` returns to the prompt with no output at all.
- **Cause:** a `&&` chain prints nothing when a test fails. Here the generic search `git log -S'@gmail.com'` matched two commits (`db69da5`, `21d6845`) that belong to the original project and are already in `origin/main`, so the guard stopped the push. Nothing was wrong with our commits.
- **Fix:** find which test failed by running each check on its own (`echo "${#ACCT}"`, `git log --oneline -S"$ACCT"`, `git branch -a --contains <hash>`), then guard on your own values instead: the account ID and the budget e-mail read from `terraform.tfvars` (runbook 4.4). Also confirm those variables are not empty.
- **Prevent:** end a guarded chain with `|| echo "NOT pushed ..."` so a stop is visible; search for your own address, not a domain.

### G-5 Old files appear unstaged next to new commits
Intended: `data/products.json`, `frontend/react-app/package.json` and `frontend/react-app/src/aws-config.js` are modified locally and left out (decision D6, open item O-6).

---

## A: AWS

### A-1 ECR scan fields are null right after a push
- **Cause:** the scan had not finished. A timing lag only.
- **Fix:** wait a few minutes, rerun the scan-findings command (runbook section 5). It then shows `COMPLETE`.

### A-2 Leftover resources from the manual build
Name collisions are avoided on purpose (our names are `ecommerce-prod-*`, the VPC is `10.20.0.0/16`). List commands: runbook section 9. No delete decision has been made.

### A-3 State bucket policy missing
- **Symptom:** `get-bucket-policy` returns `NoSuchBucketPolicy`.
- **Cause:** the policy step in the bootstrap had been skipped.
- **Fix:** apply the HTTPS-only policy (runbook section 2).

### A-4 "The bucket is deleted" but Terraform plans to create it
Expected: the frontend bucket from the manual build was deleted by hand, so the new one is created fresh. Check the bucket name in the plan is the one you intend.

---

## N: npm and the frontend build

### N-1 `npm ci` fails: lock file and package.json out of sync *(mine: my first two explanations of the cause were wrong; the last paragraph of Cause has the verified one)*
- **Symptom (2026-10-28, first run of `scripts/deploy-frontend.sh --dry-run`):** after a page of yellow `npm warn ERESOLVE overriding peer dependency` lines, `npm error code EUSAGE ... npm ci can only install packages when your package.json and package-lock.json are in sync ... Invalid: lock file's typescript@7.0.2 does not satisfy typescript@4.9.5`.
- **Cause:** `package-lock.json` pinned TypeScript 7.0.2 while the project asks for 4.9.5, so the two files disagreed and the strict install (`npm ci`) refused to run. My first guess was that the user's local edits to `package.json` caused it; the diff showed otherwise (it only drops the `react-app/jest` ESLint preset and a trailing newline). My second guess was that the lock file was committed and out of date; that was also wrong. **Verified 2026-10-28:** `git ls-files frontend/react-app/package-lock.json` prints nothing (the file is not tracked) and `git check-ignore -v` reports `.gitignore:3:package-lock.json`. So the lock file is a local, git-ignored file that was generated at some earlier time and had gone stale.
- **Fix:** `cd frontend/react-app && npm install` once. It resolves the dependencies and rewrites the local `package-lock.json`, after which `npm ci` works. Because the file is git-ignored it never appears in `git status`, so there is nothing to commit or to avoid committing.
- **Ignore:** the yellow `npm warn ERESOLVE` lines (React 19 against a library that lists React up to 18) are warnings, not errors.
- **Prevent:** the project's `.gitignore` ignores `package-lock.json`, so a fresh clone has no lock file and `npm ci` cannot be used there (the script falls back to `npm install`, and builds are not reproducible). If the frontend is ever built in CI, stop ignoring the lock file and commit one that matches `package.json`.

## M: The original manual deployment

These were fixed before the Terraform work started.

### M-1 Cart and products not reachable from the website
- **Symptom:** requests from the site blocked in the browser; cart unreachable.
- **Cause:** CORS configuration mismatch between the site origin and the API (headers and allowed origin).
- **Fix carried forward:** in Terraform the API Gateway CORS list is explicit (decision D24), and the frontend is served from a CloudFront domain that must be in the allowed origins. Re-test for CORS errors in the browser console in the paid session.

### M-2 Product images not showing
- **Symptom:** images missing; CloudFront returned `x-cache: Miss` and a failure on the image path.
- **Cause:** the product records pointed at image URLs that did not exist at the CloudFront path (the bucket objects, the `images/products/` prefix and the stored `image_url` values disagreed).
- **Fix carried forward:** the `frontend` module uploads the 20 images to a known prefix, and the `catalog` module builds the `image_url` values from the CloudFront domain, ignoring the values in `products.json` (decision D16). Verified: 20 items and one working image URL.
- **Prevent:** after any frontend upload, never run `aws s3 sync --delete` against the whole bucket (it would remove `images/products/`), and invalidate CloudFront after changing `index.html`.

---

## Quick reference: "I think something is wrong"

| Check | Command | Good result |
|---|---|---|
| Folder | `pwd` | ends in `terraform/envs/prod` |
| Files filled | `wc -l ../../modules/<name>/*.tf` | none is 0 |
| Stale plan | `rm -f tfplan` | no output |
| Valid | `terraform validate` | `Success!` |
| Drift | `terraform plan -target=module.<name>` | `No changes.` |
| Git | `git status --short` | only the three old files plus current work |
| Secrets | `git check-ignore -v terraform/envs/prod/backend.hcl terraform/envs/prod/terraform.tfvars` | two lines |
| Billing | the three billing checks (runbook section 8.4) | `[]` |
