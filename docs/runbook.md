# Runbook

How to set up, change, deploy and tear down the ecommerce stack. What each module builds and why is in [`decision-log.md`](decision-log.md); resource counts are in the README status tables. Problems and fixes are in [`troubleshooting.md`](troubleshooting.md).

Status markers: ✅ output seen and checked, ◐ ran but output not seen, 📝 written, not applied, ⏳ not started. 💲 marks something that bills while it exists.

---

## 0. Conventions

**Shell.** Git Bash on Windows. Paste **one line at a time** and wait for the prompt. Multi-line pastes sometimes glue two lines together (see `troubleshooting.md` S-1).

**Where to run what.** Two folders matter. This command takes you to the right one from anywhere inside the repo, so use it instead of typing relative paths:

```bash
cd "$(git rev-parse --show-toplevel)"                       # repo root: git add, git commit, scripts
cd "$(git rev-parse --show-toplevel)/terraform/envs/prod"   # Terraform working folder: init, plan, apply
pwd                                                          # confirm; the path must end in the folder you meant
```

The prompt also shows the folder, for example `.../ecommerce-web-app/terraform/envs/prod (terraform-prod)`.

**Never run Terraform from `terraform/modules/*`.** Modules are only called from `envs/prod`.

**Git Bash path conversion.** Before AWS commands that contain `/`-style strings (ARNs, policies), run this once per terminal:

```bash
export MSYS_NO_PATHCONV=1
```

**Placeholders.** `<ACCOUNT_ID>`, `<BUDGET_EMAIL>`, `<IMAGE_TAG>`. Find your account ID with `aws sts get-caller-identity --query Account --output text`.

**Pager.** If a git command ends in a `:` prompt, press `q`. Add `--no-pager` after `git` to avoid it: `git --no-pager log --oneline -5`.

**Sharing output safely.** Before pasting command output anywhere public, pipe it through a `redact` function that swaps 12-digit account IDs, e-mail addresses and access-key IDs for placeholders. One-time setup (Git Bash, one line, then reload):

```bash
echo 'redact() { sed -E "s/[0-9]{12}/<ACCOUNT_ID>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+/<EMAIL>/g; s/AKIA[0-9A-Z]{16}/<ACCESS_KEY>/g"; }' >> ~/.bashrc
source ~/.bashrc
echo "acct 123456789012 mail a@b.com" | redact
```

The test line must print `acct <ACCOUNT_ID> mail <EMAIL>`. Use it as `terraform plan ... | redact | tee ~/plan.txt`. It does not catch everything (CloudFront domains, pool and client IDs, resource names), and it can never make a real secret safe to share: passwords and secret access keys must not be pasted at all.

---

## 1. Toolchain

| Tool | Version in use | Check | Notes |
|---|---|---|---|
| AWS CLI | 2.32.7 | `aws --version` | Default region `us-east-1`. Check with `aws configure get region` |
| Git | 2.52.0.windows.1 | `git --version` | |
| Docker Desktop | 29.0.1 (WSL2 backend) | `docker --version` and **`docker info`** | The CLI prints a version even when the engine is stopped. Only `docker info` showing a `Server:` section proves the engine runs |
| Chocolatey | 2.6.0 | `choco --version` | |
| Terraform | **1.16.6** (stable, pinned) | `terraform -version` | See below |
| AWS provider | 6.69.1 | in `.terraform.lock.hcl` | `~> 6.0` |
| random provider | `~> 3.6` | in `.terraform.lock.hcl` | Added with the database module |

### Install or repair Terraform with Chocolatey ✅

Run in an **administrator** PowerShell (Start menu, right-click PowerShell, Run as administrator).

```powershell
choco search terraform --exact --all-versions        # confirm the version exists
choco upgrade terraform --version=1.16.6 --allow-downgrade -y
choco pin add --name=terraform --version=1.16.6      # stop "choco upgrade all" from moving it
choco pin list                                       # expect: terraform|1.16.6
```

Then in a **new** Git Bash terminal (an old one keeps its old PATH):

```bash
terraform -version        # expect: Terraform v1.16.6, no -alpha, -beta or -rc
which terraform
```

Do not use a plain `choco upgrade terraform -y` when a pre-release is installed. It stays on the pre-release track and moves to the newest release candidate (`troubleshooting.md` W-2).

To upgrade on purpose later: `choco pin remove --name=terraform`, upgrade to a specific version, pin again, then update `required_version` in `terraform/envs/prod/versions.tf`.

### Check the AWS login ✅

```bash
aws sts get-caller-identity        # shows the account and identity the CLI uses
aws configure get region           # expect us-east-1
```

---

## 2. Remote state bucket (bootstrap, done once) ✅

Terraform keeps a state file listing everything it built. It contains secrets (the database password), so it lives in a private, versioned, encrypted S3 bucket. Terraform cannot create the bucket that holds its own state, so this one bucket is made by hand. It is not managed by Terraform, so `terraform destroy` never touches it.

Creates one S3 bucket, a few cents a month at most.

```bash
export MSYS_NO_PATHCONV=1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="tfstate-${ACCOUNT_ID}-us-east-1"
echo "$BUCKET"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
```

For `us-east-1` do not pass a `LocationConstraint`. Success prints a JSON block with `Location`.

```bash
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

| Command | Why |
|---|---|
| versioning | Keeps every earlier version of the state file, so a bad apply can be rolled back |
| encryption | Encrypts at rest |
| public access block | Makes it impossible for the bucket to become public by accident |

HTTPS-only policy (refuses any request that is not HTTPS):

```bash
POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyInsecureTransport\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":[\"arn:aws:s3:::${BUCKET}\",\"arn:aws:s3:::${BUCKET}/*\"],\"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}}]}"

aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$POLICY"
```

Verify all four settings (read-only):

```bash
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws s3api get-bucket-encryption --bucket "$BUCKET" --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" --output text
aws s3api get-public-access-block --bucket "$BUCKET" --query "PublicAccessBlockConfiguration" --output json
aws s3api get-bucket-policy --bucket "$BUCKET" --query "Policy" --output text
```

Expected: `"Status": "Enabled"`, then `AES256`, then four `true` values, then the policy containing `DenyInsecureTransport`.

**What happened the first time:** the policy step was skipped and `get-bucket-policy` returned `NoSuchBucketPolicy`. The policy was applied afterwards (`troubleshooting.md` A-3).

---

## 3. Repository layout and local-only files

```
ecommerce-web-app/                  repo root
├── .gitignore
├── scripts/
│   └── build-and-push.sh           builds and pushes the four images
├── services/<name>-service/        each has Dockerfile and a .dockerignore
├── data/products.json              seed data (image_url values are ignored, see catalog module)
├── frontend/react-app/
├── docs/                           these documents
└── terraform/
    ├── envs/prod/                  run every Terraform command here
    │   ├── versions.tf  variables.tf  main.tf  outputs.tf
    │   ├── .terraform.lock.hcl     COMMIT this
    │   ├── backend.hcl             gitignored: the state bucket name
    │   └── terraform.tfvars        gitignored: local settings
    └── modules/
        network  cognito  frontend  ecr  data  catalog  messaging
        iam  budget  security  database  alb  ecs  api
```

Every module folder holds exactly `main.tf`, `variables.tf`, `outputs.tf` (plural names; the `catalog` module has no outputs file). Anything else, such as a file named just `.tf`, a `.terraform` folder or a `terraform.tfstate*` file, is a mistake. Check with `ls -a terraform/modules/<name>`.

### `.gitignore` entries for Terraform

```
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
backend.hcl
tfplan
*.tfplan
crash.log
```

`*.tfplan` matters because `destroy.tfplan` is not matched by plain `tfplan`. `.terraform.lock.hcl` must **not** be ignored.

Check that the sensitive files are ignored. `git check-ignore` needs a file name:

```bash
git check-ignore -v terraform/envs/prod/backend.hcl terraform/envs/prod/terraform.tfvars
```

It must print one line for each, naming the rule. Nothing printed means the file is not protected: stop.

### `backend.hcl` (local only)

```
bucket = "tfstate-<ACCOUNT_ID>-us-east-1"
```

`versions.tf` holds the rest of the backend settings (`key`, `region`, `encrypt`, `use_lockfile`). The bucket name stays out of git (decision D12). Every `init` needs `-backend-config=backend.hcl`.

### `terraform.tfvars` (local only)

```
single_nat_gateway = true
allow_destroy      = true
budget_email       = "<BUDGET_EMAIL>"
image_tag          = "<IMAGE_TAG>"
```

| Setting | Meaning |
|---|---|
| `single_nat_gateway` | `true` = one NAT gateway (practice, cheaper). Code default `false` = one per zone (production) |
| `allow_destroy` | `true` = practice mode: deletion protection off, buckets and registries may be emptied on destroy, no final database snapshot. Code default `false` = everything locked |
| `budget_email` | Where the budget alerts go. Kept out of git because the repo is public |
| `image_tag` | Container image tag to deploy. Update it every time you push new images |

Write it with `printf`, not by hand, when adding a line. The file may end without a newline, and a plain append can glue the new text onto the last line:

```bash
printf '\nimage_tag = "<IMAGE_TAG>"\n' >> terraform.tfvars
cat terraform.tfvars
terraform fmt           # aligns the = signs; prints the file name if it changed anything
```

---

## 4. Standard workflows

### 4.1 Start of a session

```bash
cd "$(git rev-parse --show-toplevel)"
git status --short                    # expect only the 3 old modified files, plus whatever you are working on
git --no-pager log --oneline -5
docker info >/dev/null 2>&1 && echo "docker engine OK" || echo "docker engine NOT running"      # only if you will build images
aws sts get-caller-identity --query Account --output text        # confirm the CLI still has credentials
cd terraform/envs/prod
terraform init -backend-config=backend.hcl                        # safe to repeat; needed after adding a module
```

### 4.2 The change loop (every change, every module)

```bash
cd "$(git rev-parse --show-toplevel)/terraform/envs/prod"
ls -a ../../modules/<name>                              # exactly main.tf outputs.tf variables.tf
wc -l ../../modules/<name>/*.tf                         # no file may show 0
rm -f tfplan                                            # remove any stale plan first
terraform init -backend-config=backend.hcl
terraform fmt -recursive ../..                          # fixes spacing; prints names of files it changed
terraform fmt -check -recursive ../..                   # must print nothing
terraform validate                                      # expect: Success! The configuration is valid.
terraform plan -target=module.<name> -out=tfplan
terraform show tfplan                                   # read it; add | grep "^  # " for a one-line-per-resource list
```

Read the plan for these things:
- The `Plan: X to add, Y to change, Z to destroy.` line matches the resource counts in the README status tables.
- No `destroy` or `replace` (`-/+`) you did not expect.
- Every setting that comes from `terraform.tfvars` shows the value you intended (`deletion_protection`, `force_destroy`, `force_delete`, `image_tag`).
- Any warning other than "Resource targeting is in effect" is explained.

Then, only for modules that are meant to exist now:

```bash
terraform apply tfplan
terraform plan -target=module.<name>                    # drift check; expect: No changes.
```

Notes:
- `-target` limits the plan to a module **plus everything it depends on**. A security-group module therefore drags the VPC into its plan. That is why several plans in this project show "14 to add" when the module has 13 resources.
- A plain `terraform plan` without `-target` compares everything. While the network is down it lists the network and everything that depends on it as "to add". That is correct, not an error.
- Apply a saved plan: it runs exactly what you reviewed and does not ask for confirmation. Editing any `.tf` file or `terraform.tfvars` after planning makes the saved plan stale. Terraform then refuses it, so plan again.
- `terraform show tfplan` hides sensitive values. `terraform show -json tfplan` does not. If you create `plan.json`, delete it afterwards (`rm plan.json`), because it is not gitignored.

Reading a saved plan without recomputing it (local, read-only):

```bash
terraform show tfplan | grep "Plan:"
terraform show tfplan | grep -E "force_delete|deletion_protection"
terraform show tfplan | grep -c "<text to count>"
```

### 4.3 Committing a module

Always from the repo root, always by explicit path, and with a staged-file count check:

```bash
cd "$(git rev-parse --show-toplevel)"
git status --short                                      # see what changed; terraform.tfvars must NOT appear
git add terraform/modules/<name> terraform/envs/prod/main.tf       # add other files by name as needed
git diff --cached --name-only                           # the staged list
[ "$(git diff --cached --name-only | wc -l)" -eq <N> ] && git commit -m "<message>"
git --no-pager log --oneline -3
```

`<N>` is the number of files you expect to be staged. If the count differs, the commit is skipped and nothing is lost. Typically N = 3 module files + 1 (envs/prod `main.tf`) = 4, plus `variables.tf`, `outputs.tf` or `versions.tf` when you changed those.

In `git status --short` the **left column** is the staging area and the **right column** the working folder: `M ` is staged, ` M` (leading space) is modified but not staged, `A ` is a new staged file, `??` is untracked. The three old files stay ` M` on purpose (decision D6).

`warning: LF will be replaced by CRLF` is harmless Windows line-ending news. Add a `.gitattributes` before CI work.

### 4.4 End of a session

1. Destroy anything that bills (section 8), then run the three billing checks.
2. `git status --short` should list only the three old modified files.
3. `git push` puts the commits on GitHub (it never touches AWS). The repository is public and history cannot be cleaned up easily once pushed, so check first that no commit holds the account ID or e-mail. Both history checks print a sentence only when clean:
   ```bash
   ACCT=$(aws sts get-caller-identity --query Account --output text)
   [ -z "$(git log --oneline -S"$ACCT")" ] && echo "account ID not in history"
   BEMAIL=$(sed -n 's/^budget_email *= *"\(.*\)"/\1/p' terraform/envs/prod/terraform.tfvars)
   [ -n "$BEMAIL" ] && [ -z "$(git log --oneline -S"$BEMAIL")" ] && echo "e-mail not in history"
   ```
   Search for your own address (read from `terraform.tfvars`), not for `@gmail.com`: the generic search matches two commits from the original project (`db69da5`, `21d6845`) and blocked the first push for no good reason (troubleshooting G-6). Check that `$BEMAIL` and `$ACCT` are not empty (`echo "${#BEMAIL} ${#ACCT}"`), otherwise an empty result proves nothing. A one-line guarded push:
   ```bash
   [ -n "$BEMAIL" ] && [ -n "$ACCT" ] && [ -z "$(git log --oneline -S"$BEMAIL")" ] && [ -z "$(git log --oneline -S"$ACCT")" ] && git push || echo "NOT pushed: a check failed or the push was refused"
   ```
   For the current tree use `git grep -c "$ACCT" || echo "not in tree"`. A hit in `.terraform.lock.hcl` for `[0-9]{12}` is hash noise, not an account ID. Then `git push -u origin terraform-prod` the first time (sets the upstream), plain `git push` afterwards. Checked on 2026-10-23 for `terraform` and `scripts` (tree and history): clean.

---

## 5. Building and pushing the container images ✅

Terraform does not build Docker images. A script does, and it pushes to the ECR repositories that the `ecr` module created.

Files (committed in `0601b5b`):
- `services/<name>-service/.dockerignore` for each of the four services: `.env*`, `__pycache__/`, `*.pyc`, `.git`, `venv/`, `.venv/`. Without it, `COPY . .` in the Dockerfile would bake a local `.env` file (which the services read) into the image.
- `scripts/build-and-push.sh`.

What the script does, in order:
1. Refuses to run if `services/` has uncommitted changes. The tag is the git commit, so the tag must match the code.
2. Tags images with the first 12 characters of the current commit (`git rev-parse --short=12 HEAD`).
3. Logs Docker in to ECR (`aws ecr get-login-password | docker login`).
4. For each service: skips it if that tag already exists in ECR (tags are immutable), otherwise `docker build --platform linux/amd64` and `docker push`.

Run it:

```bash
docker info >/dev/null 2>&1 && echo "docker engine OK" || echo "docker engine NOT running"     # engine must be running
cd "$(git rev-parse --show-toplevel)"
bash scripts/build-and-push.sh
```

The first run is slow (base image download). It ends with `Done. Image tag: <tag>`. Write the tag down.

Check the script before running it:

```bash
bash -n scripts/build-and-push.sh && echo "syntax OK"      # syntax check without running
grep -c $'\r' scripts/build-and-push.sh                     # want 0; anything else means CRLF line endings
```

If bash reports `$'\r': command not found`, fix the endings: `sed -i 's/\r$//' scripts/build-and-push.sh`. In Kiro, the status bar shows CRLF or LF at the bottom right.

Verify what landed in ECR (read-only):

```bash
for s in product cart order user; do echo "== ${s}-service"; aws ecr describe-images --region us-east-1 --repository-name "ecommerce-prod/${s}-service" --query 'imageDetails[].{tags:imageTags,pushed:imagePushedAt,bytes:imageSizeInBytes}' --output json; done
```

Vulnerability scan results (the scan runs by itself on push; results can lag a few minutes):

```bash
for s in product cart order user; do echo "== ${s}-service"; aws ecr describe-image-scan-findings --region us-east-1 --repository-name "ecommerce-prod/${s}-service" --image-id imageTag=<IMAGE_TAG> --query '{status:imageScanStatus.status,counts:imageScanFindings.findingSeverityCounts}' --output json; done
```

List the HIGH findings of one image:

```bash
aws ecr describe-image-scan-findings --region us-east-1 --repository-name ecommerce-prod/product-service --image-id imageTag=<IMAGE_TAG> --query 'imageScanFindings.findings[?severity==`HIGH`].{cve:name,pkg:attributes[?key==`package_name`]|[0].value,ver:attributes[?key==`package_version`]|[0].value}' --output table
```

Result so far: all four images showed identical counts (3 HIGH, 9 MEDIUM, 3 LOW). The HIGH findings are two in `glibc` and one in `zlib`, which are Debian system libraries in the shared `python:3.11-slim` base image, not the app code. See open item O-4.

**Rebuild checklist (open item O-3; done 2026-10-23 as tag `64d6332f100d`, `--pull` is now in the script; `image_tag` update and ECS re-plan still to do).** The current images are tagged `89b8b8da0ee6`, a commit hash that no longer exists on the branch, because the commit was amended afterwards. The code is identical, but before the paid session:
1. Make sure everything is committed and the commit is final (no more amends).
2. Add `--pull` to the `docker build` line in `scripts/build-and-push.sh` so the newest base image is fetched. Commit that change.
3. Run the script, note the new tag.
4. Put the new tag in `terraform.tfvars` as `image_tag`.

---

## 6. Planned, not built yet ⏳

### 6.1 SSM parameters (open item O-2)

The services read their settings from Parameter Store under `/ecommerce/prod/`. The IAM module already grants access to exactly these names:

| Parameter | Type | Value | Read by |
|---|---|---|---|
| `/ecommerce/prod/aws/region` | String | `us-east-1` | all four |
| `/ecommerce/prod/db/host` | String | database address (`module.database` output `address`) | user, order |
| `/ecommerce/prod/db/password` | **SecureString** (our KMS key) | generated password (`module.database` output `password`) | user, order |
| `/ecommerce/prod/user-service-url` | String | `http://<ALB DNS name>` (no path) | order |
| `/ecommerce/prod/cart-service-url` | String | `http://<ALB DNS name>` | order |
| `/ecommerce/prod/product-service-url` | String | `http://<ALB DNS name>` | order |
| `/ecommerce/prod/sns/topic-arn` | String | `module.messaging` output `topic_arn` | order |

Confirmed against each service's `config.py` on 2026-10-23 (grep of `get_parameters`): product and cart read only `aws/region`; user reads `aws/region`, `db/host`, `db/password`; order reads all seven. The names are built as `/ecommerce/{environment}/...`, so the `environment` value the container receives must be `prod`. Confirmed from `config.py`: `environment` defaults to `"local"`, and when it is `"local"` the SSM lookup is skipped entirely, so the ECS task definition must set `ENVIRONMENT=prod`. The ecs module sets `ENVIRONMENT = var.env` and `AWS_REGION` for every container (confirmed 2026-10-23); the value passed as `env` from the root still has to be `prod`. The order service appends its own paths (`/users/cognito/{id}`, `/cart`, `/products/{id}/inventory`), so the three URL parameters must be the bare base `http://<ALB DNS name>` with no path and no trailing slash. These calls go service to ALB directly, not through API Gateway, so the ALB listener rules must match those exact paths. Confirmed 2026-10-23: the patterns are `/products*`, `/cart*`, `/users*`, `/orders*`, which match plain `/cart` as well as `/cart/items`. The root passes `env = var.env` to the modules and does not pass `db_name`, so the `db_name` default in the database module is what is used. Both defaults confirmed 2026-10-23: `db_name` = `ecommercedb` (matches the code default) and root `env` = `prod`. Every assumption behind the SSM parameters is now verified against the code. Both user and order read with `WithDecryption=True`, so a SecureString is fine. `db_name` defaults to `ecommercedb` and `db_user` to `postgres`; the database module must create exactly those, or the task must override them (to verify). If a lookup fails, the services only print a warning and use localhost defaults (`decision-log.md` F-4).

### 6.2 API Gateway ⏳

Plan reviewed 2026-10-22: `Plan: 23 to add, 0 to change, 0 to destroy` (16 in the module, 7 pulled in as dependencies). Design details are in `decision-log.md` (D24). Committed as `be88453`. Not applied yet; it is part of the paid session (section 8.2, stage 7). After the apply, `terraform output api_endpoint` gives the URL that goes into the frontend config.

### 6.3 Frontend deploy (open item O-5) ⏳

1. Generate `frontend/react-app/src/aws-config.js` with `bash scripts/configure-frontend.sh`. It reads the outputs `cognito_user_pool_id`, `cognito_client_id` and `api_endpoint`, checks that none is empty and that the API address starts with `https://`, strips a trailing slash, and writes the file (through a temporary file, so a failure leaves the old one untouched). Do not type the IDs by hand: the file currently holds IDs from the deleted manual build. Until the API module is applied the script stops with `ERROR: terraform output 'api_endpoint' is empty or missing`; that is the expected result before the paid session. The generated file is never committed (decision D6): it is one of the three old modified files, and git keeps showing it as modified. The app sends the Cognito ID token (`api.js`, confirmed 2026-10-23), which is what the authorizer needs (D24).
2. Build, upload and invalidate with one script: `bash scripts/deploy-frontend.sh` (or `bash scripts/deploy-frontend.sh --dry-run` first, which builds and only lists what the upload would copy or delete). What it does, in order:
   - runs `configure-frontend.sh` (step 1), then reads `frontend_bucket`, `cloudfront_id` and `cloudfront_domain` from Terraform;
   - `npm ci` (or `npm install` if there is no `package-lock.json`), then `npm run build`; it stops if `build/index.html` is missing. `npm ci` took about 10 minutes on the OneDrive folder, so when `node_modules` is already current run `SKIP_INSTALL=1 bash scripts/deploy-frontend.sh` to skip the install. The very first time, `npm ci` failed because a stale, git-ignored local `package-lock.json` did not match `package.json`; run `npm install` once in `frontend/react-app` (troubleshooting N-1). The lock file is ignored by git, so it never needs committing;
   - counts the objects under `images/products/` (expected 20);
   - uploads `build/static` with a one-year immutable cache header and **no delete** (visitors holding an older page still need the old hashed files), then uploads everything else with `no-cache` and `--delete`, excluding `static/*` and `images/*` so the product images can never be deleted;
   - counts the product images again and fails if the number changed;
   - invalidates only `/index.html` (the edge function maps extension-less paths to it); the script sets `MSYS_NO_PATHCONV=1` so Git Bash does not turn that path into a Windows path.
   Tested against stand-ins for `terraform`, `aws` and `npm` on 2026-10-23 (dry run, real run, missing build output, changed image count). It has not been run against real AWS, and until the API module is applied it stops at step 1 with the `api_endpoint` error.
3. (Folded into step 2.)
4. (Folded into step 2.)
5. Check a deep link such as `/cart`: it should return the app's `index.html` (the edge function rewrites only paths without a file extension).

### 6.4 Tests in the paid session ⏳

| Test | Expected |
|---|---|
| Product list in the browser | 20 products, images load |
| Sign up and log in | Works. The first call to `/users/profile` auto-creates the user row in PostgreSQL |
| Which token the frontend sends | The Cognito **ID token** in the `Authorization` header. An access token is rejected with 401 (decision D24) |
| Add to cart, place an order | Order appears under Orders; stock drops |
| `curl -i <api>/cart` with no token | **401** (the services trust any token, so this proves the authorizer protects them; finding F-1) |
| `curl -i <api>/products/prod-001/inventory -X PUT` | 404 from API Gateway (internal routes are not exposed) |
| Browser console | No CORS errors |
| Product service logs | No access-denied from KMS or DynamoDB (if there is, the IAM policy is too tight: one-line fix, no rebuild) |

---

## 7. Cost control

Rough figures from memory, **not verified**. Check the AWS pricing pages.

| Item | Idle cost |
|---|---|
| NAT gateway 💲 | about $0.045 an hour each, plus data |
| Internal load balancer 💲 | hourly charge while it exists |
| RDS `db.t4g.micro`, single zone 💲 | hourly charge while it exists |
| Fargate, four 0.25 vCPU / 0.5 GB tasks 💲 | hourly charge while running |
| KMS customer key | about $1 a month |
| DynamoDB on demand, S3, CloudFront, Cognito, SNS, IAM, ECR (four small images) | cents a month at this size |
| Budget | alerts only, does not stop anything. First two budgets are free as far as known; confirm on the billing page |

Earlier estimate for the paid stack at practice size: about $0.15 an hour; at production size (two NATs, Multi-AZ database, two tasks each) about $0.35 an hour. Forgotten for a month the practice stack would cost well over $100.

The budget alert is a smoke alarm, not a circuit breaker. The real protection is destroying the paid stack after each session.

---

## 8. Paid session procedure and teardown ✅ (run once, 2026-10-28)

First run completed on 2026-10-28: all nine stages applied in the order below, every stage check passed, the browser tests passed, and the teardown (91 resources, section 8.3) left the six-section billing check empty. Things that needed attention that day: the `rds.force_ssl` apply-method drift (troubleshooting T-21) and `npm ci` (N-1). Notes for the next run: the database stage is the slowest; ECS services came up healthy in about three minutes with a 120-second grace period; `npm ci` takes about 10 minutes unless `SKIP_INSTALL=1` is used.

### 8.1 Before starting

- Images rebuilt and tagged, `image_tag` updated (section 5).
- SSM module, API module and the frontend config step done in code (section 6).
- Full plan reviewed: `terraform plan -no-color | grep -E "^Plan:"` shows the expected total. Last full plan (2026-10-27, untargeted, with the images tagged `64d6332f100d`): **`Plan: 91 to add, 0 to change, 0 to destroy.`** No change or destroy means every already-built module (cognito, frontend, ecr, data, catalog, messaging, iam, budget) matches the code. Redo the plan right before applying if any `.tf` file or `terraform.tfvars` changed since.
- Budget alert is active.

### 8.2 Apply in stages (check each before the next)

Use `-out=tfplan` and `terraform show tfplan` every time.

Order (corrected 2026-10-27: the SSM parameters need the load balancer's DNS name, so they come after `alb`, and before `ecs` because the services read their settings only once, at startup, decision D27):

| # | Module | Expected `Plan:` (targeted) | Check before the next stage |
|---|---|---|---|
| 1 | `network` 💲 (NAT starts billing) | 26 to add | `aws ec2 describe-vpcs --filters Name=cidr,Values=10.20.0.0/16 --query "Vpcs[].VpcId" --output text` shows one VPC; `aws ec2 describe-nat-gateways --filter Name=state,Values=available --query "NatGateways[].NatGatewayId" --output text` shows one NAT |
| 2 | `security` | 13 to add | 4 security groups named `ecommerce-prod-*-sg` exist |
| 3 | `database` 💲 (takes the longest, often 5 to 15 minutes) | 6 to add | `aws rds describe-db-instances --query "DBInstances[].{id:DBInstanceIdentifier,status:DBInstanceStatus,multiaz:MultiAZ}" --output table` shows `available` and `False` |
| 4 | `alb` 💲 | about 10 to add | load balancer state `active`; four target groups |
| 5 | `ssm` | 7 to add | `aws ssm get-parameters-by-path --path /ecommerce/prod --query "Parameters[].Name" --output text` lists 7 names; the three service URLs start with `http://` and have no path |
| 6 | `ecs` 💲 | about 13 to add | every service reaches its desired count; every target `healthy` (`/health`) |
| 7 | `api` | 16 to add | `terraform output -raw api_endpoint`, then `curl` of `<api>/products` returns the catalogue |
| 8 | Frontend build, upload, invalidate (section 6.3) | not Terraform | `scripts/deploy-frontend.sh --dry-run`, then the real run |
| 9 | Tests (section 6.4) | | all rows pass |

For each stage use the change loop (section 4.2): `rm -f tfplan`, `plan -target=module.X -out=tfplan`, read it, `apply tfplan`, drift check. Counts are approximate; what must hold is **0 to change and 0 to destroy**.

**If a stage fails.** The saved plan may have been partly applied; nothing is lost. Read the error, fix the cause in code (or the environment), `rm -f tfplan`, plan again (it shows only what is left), apply again. Never use `-auto-approve`, and never destroy to "start over". If the AWS login expires mid-apply, log in again and re-plan. If Terraform reports a state lock after an interrupted run, check no other Terraform process is running before `terraform force-unlock <ID>`. **Stop-the-clock rule:** if the stack is not working after about 30 minutes of trying, tear down the paid modules (section 8.3) and continue another day.

### 8.3 Destroy

**Do not run an untargeted `terraform destroy`.** With `allow_destroy = true`, everything is destroyable, so it would delete the Cognito pool and its users, the DynamoDB tables and data, the frontend bucket and the KMS key (which is scheduled for deletion). The earlier network-only destroy was safe only because the network was the only thing in state at the time.

Destroy only the paid modules (read the plan first: every line must be one of these modules):

```bash
cd "$(git rev-parse --show-toplevel)/terraform/envs/prod"
terraform plan -destroy -target=module.api -target=module.ssm -target=module.ecs -target=module.alb -target=module.database -target=module.security -target=module.network -out=destroy.tfplan -no-color | tee ~/destroy-plan.txt | grep -E "^Plan:"
terraform show -no-color destroy.tfplan | grep -E "^  # " | cut -d. -f2 | sort | uniq -c
terraform apply destroy.tfplan
```

Terraform labels a destroy run "Apply complete!". That is normal. The `ssm` module is in the target list on purpose: its parameters would otherwise point at servers that no longer exist.

Expected and seen on 2026-10-28: `Plan: 0 to add, 0 to change, 91 to destroy.` with the per-module counts alb 10, api 16, database 6, ecs 13, network 26, security 13, ssm 7 and **no other module name**. If any other module appears (`data`, `cognito`, `frontend`, `ecr`, `iam`, `catalog`, `messaging`, `budget`), do not apply.

After the destroy, a plain `terraform plan -no-color | grep -E "^Plan:|will be destroyed|will be updated"` must show `Plan: 91 to add, 0 to change, 0 to destroy.` and nothing about destruction: that proves only the paid pieces were removed. If the destroy stops on a dependency error (a security group or subnet still in use by a network interface that is releasing), wait a few minutes and apply again.

### 8.4 Three billing checks (all must print `[]` or nothing) ✅ (used after the first network destroy)

```bash
aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId'
aws ec2 describe-addresses --query 'Addresses[].AllocationId'
aws ec2 describe-vpcs --filters Name=cidr,Values=10.20.0.0/16 --query 'Vpcs[].VpcId'
```

Add after the paid session exists: load balancers, RDS instances, ECS clusters.

```bash
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName"
aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text
aws ecs list-clusters
```

A NAT gateway can show as `deleted` for up to an hour in other queries. Only `available` and `pending` bill.

Baseline before the first paid session (2026-10-27): load balancers, NAT gateways, Elastic IPs, secrets, RDS instances and ECS clusters were **all empty**. The same single line, used as the after-picture, must give the same empty result:

```bash
echo "== LOAD BALANCERS"; aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName" --output text; echo "== NAT"; aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query "NatGateways[].NatGatewayId" --output text; echo "== ELASTIC IPS"; aws ec2 describe-addresses --query "Addresses[].AllocationId" --output text; echo "== SECRETS"; aws secretsmanager list-secrets --query "SecretList[].Name" --output text; echo "== RDS"; aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text; echo "== ECS"; aws ecs list-clusters --query "clusterArns" --output text
```

---

## 9. Inventory and cleanup of leftovers

Run these read-only commands to see what exists outside Terraform. **No deletion has been approved** (open item O-7), so there are no delete commands here.

```bash
aws s3 ls
aws cloudfront list-distributions --query "DistributionList.Items[].{Id:Id,Domain:DomainName,Comment:Comment}" --output table
aws dynamodb list-tables
aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text
aws ecs list-clusters
aws ec2 describe-vpcs --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" --output table
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query "NatGateways[].NatGatewayId"
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName"
aws apigatewayv2 get-apis --query "Items[].{Id:ApiId,Name:Name}" --output table
aws cognito-idp list-user-pools --max-results 20 --query "UserPools[].{Id:Id,Name:Name}" --output table
aws ecr describe-repositories --query "repositories[].repositoryName"
aws iam list-roles --query "Roles[?contains(RoleName,'ecs') || contains(RoleName,'ecommerce')].RoleName" --output text
aws ssm describe-parameters --query "Parameters[].Name" --output text
aws sns list-topics --query "Topics[].TopicArn" --output text
aws sqs list-queues
aws logs describe-log-groups --query "logGroups[].logGroupName" --output text
aws ec2 describe-addresses --query "Addresses[].{Ip:PublicIp,Attached:AssociationId}" --output table
aws budgets describe-budgets --account-id <ACCOUNT_ID> --query 'Budgets[].{Name:BudgetName,Limit:BudgetLimit.Amount,Unit:BudgetLimit.Unit}' --output table
```

Known leftovers from the manual build (from the sweeps at the start of the project). **This table is out of date:** the 2026-10-27 inventory found that the old VPC `ecomm-app` and the old CloudFront distribution were already gone. Always list before deleting; never delete from this table.

| Leftover | Why it matters | Collides with Terraform? |
|---|---|---|
| 4 ECR repos `ecommerce/order-service`, `product-service`, `user-service`, `cart-service` | Hold old images, small storage cost | No (ours are `ecommerce-prod/*`) |
| A CloudFront distribution (comment "secure domain") pointing at a deleted S3 bucket | Dangling origin. Must be disabled before AWS lets you delete it | No |
| VPC `ecomm-app`, `10.10.0.0/16` | Free, but is why the new VPC uses `10.20.0.0/16` | No |
| IAM role `ecommerce-ecs-task-role` | Old role with broad full-access policies | No (ours are `ecommerce-prod-*`) |
| A hand-made budget (`mothly-cost-budget`, $20) | Harmless second alert. Together with ours it uses the two free budgets | No |
| `ecsTaskExecutionRole` | Standard AWS role. Harmless, leave it | No |
| 11 stopped Docker containers and 25 images on the laptop | Disk space only | No |

---

## 10. Commit history on `terraform-prod`

| Commit | Message |
|---|---|
| `7a68586` | Add Terraform: remote state backend and prod network module |
| `1b732db` | Add Cognito user pool and web client module |
| `2135754` | Add frontend hosting module: private S3, CloudFront OAC, product images |
| `c3c87b0` | Add ECR repositories: immutable tags, scan on push, lifecycle policy |
| `c5eb9d6` | Add data module: KMS key and DynamoDB tables with PITR |
| `b7077b6` | Replace per-module destroy overrides with a single allow_destroy switch |
| `0601b5b` | Add catalog module; add .dockerignore files and ECR build-and-push script (amended from `89b8b8d`) |
| `219a7b8` | Add messaging module: KMS-encrypted SNS topic for order events (amended from `db8f4dc`) |
| `94c4f4c` | Add IAM module: ECS execution role and least-privilege task roles per service |
| `cfac88f` | Add budget module: monthly cost alerts at 50/80/100% and forecast |
| `4bf5f51` | Add security module: layered security groups for VPC link, ALB, ECS and RDS |
| `fc39ab0` | Add database module: encrypted single-AZ PostgreSQL with generated password; add random provider |
| `cfc009b` | Add ALB module: internal load balancer with path-based routing to four target groups |
| `a702db9` | Add ECS module: Fargate cluster, task definitions and services; make ALB output wait for listener rules |
| `be88453` | Add API Gateway module: HTTP API, VPC link, JWT authorizer, explicit routes |
| `6becc1f` | Add SSM parameters module: seven service settings under /ecommerce/prod, password as SecureString |
| `310cd44` | Fix swapped retention variables in database module; default backups to 1 day |
| `64d6332` | Pull the latest base image when building service images (`docker build --pull`) |
| `001eca3` | Add script that generates the frontend Cognito and API config from Terraform outputs |
| `e21be38` | Add script that builds the frontend and publishes it to S3 without touching product images |

Commits that were amended (`89b8b8d`, `db8f4dc`) no longer exist on the branch. The ECR images were tagged with the pre-amend hash `89b8b8da0ee6` (open item O-3).
