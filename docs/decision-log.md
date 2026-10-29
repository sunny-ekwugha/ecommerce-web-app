# Decision Log

Why each design choice was made, known risks, and findings about the app code. This log was rebuilt from the conversation after an earlier copy was lost, so the numbering is new, except that **D6** and **D12** keep the numbers used in the other documents.

---

## Decisions

**D1. Production-like, single environment `prod`, region `us-east-1`.** The goal was a realistic setup rather than a tutorial shortcut. One environment keeps cost and complexity down; the module structure allows a second one later.

**D2. Remote state in a hand-made S3 bucket** (versioned, AES256, public access blocked, HTTPS-only), with `use_lockfile = true`. State holds secrets and must be shared, protected and recoverable. S3 native locking avoids a separate DynamoDB lock table. Terraform cannot create its own state bucket, so this one is outside Terraform and survives `destroy`.

**D3. Layout: reusable `modules/*` called from one root, `envs/prod`.** Each module has `main.tf`, `variables.tf`, `outputs.tf`. Terraform runs only in the root.

**D4. Saved plans only** (`plan -out=tfplan`, then `apply tfplan`). What is applied is exactly what was reviewed.

**D5. Build in layers and plan with `-target=module.X`.** Pieces that bill are written and planned but applied only in the one paid session.

**D6. Three old modified files stay unstaged** (`data/products.json`, `frontend/react-app/package.json`, `frontend/react-app/src/aws-config.js`). They hold local edits from the manual build. Always add by explicit path so they never ride along.

**D7. Terraform pinned to the stable 1.16.6** (provider `~> 6.0`, lock file committed). Predictable builds; the release candidate was rejected (troubleshooting W-2).

**D8. Network:** VPC `10.20.0.0/16` (the old manual VPC used `10.10.0.0/16`), public and private subnets, a NAT gateway, S3 and DynamoDB gateway endpoints, VPC flow logs. `single_nat_gateway` switches between one NAT (practice) and one per zone (production). Gateway endpoints are free and keep S3 and DynamoDB traffic off the NAT.

**D9. NAT choice for practice: one NAT gateway** (user's choice), with the production value recorded in O-10.

**D10. Cognito:** user pool and web client with SRP and refresh flows only (no password-in-clear flow), MFA optional. Tokens are verified at the API Gateway JWT authorizer.

**D11. Frontend hosting:** private S3 bucket, CloudFront with origin access control, managed cache and response-header policies, and a CloudFront Function that rewrites extension-less paths to `index.html` so deep links work in the single-page app. The bucket is never public.

**D12. The state bucket name lives in `backend.hcl`, which is gitignored.** The repo is public; the account ID is part of the name and is kept out of git. Partial backend configuration is the mechanism.

**D13. ECR:** immutable tags, scan on push, lifecycle policy, four repos `ecommerce-prod/<service>-service`. Images are tagged with the git commit (12 characters) so every image maps to code. The build script refuses a dirty `services/` folder and skips a tag that already exists.

**D14. Data layer:** one customer-managed KMS key and the DynamoDB tables with point-in-time recovery. Access to the key is limited with `kms:ViaService` conditions so only the intended AWS services can use it on behalf of the task roles.

**D15. One `allow_destroy` switch** instead of per-module overrides (default `false` = locked). This replaced four separate tfvars lines that kept being missed (T-9 to T-12). `single_nat_gateway` stays separate because it is a cost choice, not a safety lock.

**D16. Catalog seeded by Terraform, image URLs generated from the CloudFront domain.** The `image_url` values in `data/products.json` came from the manual build and are ignored. Verified: 20 items, one image URL loads.

**D17. SQS dropped; SNS only.** The order service only publishes to an SNS topic; nothing consumes from a queue. Building a queue nothing reads would be dead infrastructure. The topic is encrypted with the KMS key. Add a queue when a consumer exists.

**D18. IAM:** one execution role (pull images, write logs) and four separate task roles, each limited to its own tables, the SNS topic, the KMS key and the SSM parameter paths it reads. No full-access policies (the manual build's role had them).

**D19. Cost alerts:** a $10 monthly budget with four e-mail alerts (50%, 80%, 100% actual and a forecast). The e-mail address is a gitignored variable. A budget only alerts; it does not stop spending (runbook section 7).

**D20. Security groups form a chain:** API Gateway's VPC link, then the internal ALB, then the ECS tasks, then RDS. Each allows only the previous tier on the needed port. Nothing in the data path is open to the internet.

**D21. Cheap database defaults:** PostgreSQL `db.t4g.micro`, single AZ, 20 GB, 1-day backups, 14-day log retention, generated password (`random_password`, kept in state and put into SSM as a SecureString). Production values (Multi-AZ, longer backups, bigger instance) are listed in O-10.

**D22. Internal ALB with path-based routing** to four target groups (one per service) with `/health` checks. The ALB is internal; only API Gateway reaches it through the VPC link.

**D23. ECS on Fargate:** one cluster, four task definitions and services. The wait-for-listener-rules dependency sits on the ALB module's `target_group_arns` output, not on the module call (troubleshooting T-15).

**D24. API Gateway HTTP API** with a VPC link, a JWT authorizer, explicit routes only, header mappings that **overwrite** rather than append, and an explicit CORS list. Confirmed by the plan reviewed on 2026-10-22 (23 to add; 16 are the module's own):
- **Routes (9).** Public, no authorizer: `GET /products`, `GET /products/{product_id}`. Authenticated (JWT): `GET /cart`, `POST /cart/items`, `DELETE /cart/items/{product_id}`, `GET /orders`, `POST /orders`, `GET /users/profile`, `POST /users/profile`. Internal service routes (for example inventory updates) are deliberately not exposed.
- **Two integrations,** both `HTTP_PROXY` through the VPC link to the ALB listener. Only the authenticated one sets headers, and it **overwrites** `X-User-Id`, `X-User-Email` and `X-User-Name` from the token claims (`sub`, `email`, `name`), so a client cannot supply its own values. The public one sets none.
- **CORS:** one allowed origin (the CloudFront domain), methods GET, POST, DELETE, OPTIONS, headers `authorization`, `content-type`, `x-user-email`, `x-user-id`, `x-user-name`, max age 3600 s.
- **Stage:** `$default`, auto-deploy, throttling 100 burst / 50 per second, JSON access logs (no tokens, only the `sub`) to a log group with 14-day retention.
- **Authorizer audience is the web client ID.** Cognito **ID tokens** carry that as `aud`; **access tokens** carry `client_id` instead and would be rejected. The frontend must send the ID token, and only the ID token has the `email` and `name` claims the header mappings need. Check this first if the paid-session tests return 401.
- Log group is not KMS-encrypted (acceptable for practice; add a key for production).
- Targeted plans add the dependencies, so `-target=module.api` also lists the VPC, two ECS subnets, two security groups, the ALB and its listener.

**D25. Never run an untargeted `terraform destroy`.** Practice mode makes the free-but-stateful pieces destroyable too (user pool, tables, buckets, KMS key). Destroy only the paid modules (runbook section 8.3).

**D26. Documents use placeholders** for account ID, e-mail and bucket name, and avoid writing IDs that go stale.

**D27. SSM parameters module (`ssm`), 7 parameters under `/ecommerce/prod/`.** Names were verified against the four `config.py` files (finding F-4). Six are plain `String`; `db/password` is a `SecureString` encrypted with the project KMS key (the services read it with `WithDecryption=True`). The three service-URL parameters hold the bare ALB base `http://<ALB DNS name>`, because the order service appends its own paths and the ALB rules (`/products*`, `/cart*`, `/users*`, `/orders*`) route them. Values come from module outputs (`database.address`, `database.password`, `alb.dns_name`, `messaging.topic_arn`), never typed by hand. The six `String` parameters use `insecure_value` (not `value`) so that their values are visible in plans and diffs; only the SecureString uses `value` (troubleshooting T-20). Standard-tier parameters have no charge. **Ordering risk:** the services read their settings once at startup. If a task starts before its parameters exist, it silently keeps localhost defaults until restarted. The staged apply (runbook section 8.2) puts the parameters before ECS; if they ever need to be guaranteed in a single apply, add a dependency input to the ecs module rather than a module-level `depends_on` (see T-15). Recovery if it happens: force a new deployment of the service.

**D28. Image vulnerabilities: PROPOSED 2026-10-24, awaiting the user's agreement. Accept the three HIGH findings for now, review at every rebuild.** ECR's scan of the rebuilt images (tag `64d6332f100d`, base `python:3.11-slim` on Debian 13 "trixie") reports 3 HIGH, 9 MEDIUM, 3 LOW, identical for all four services and identical to the older images. The three HIGH findings, checked on the Debian security tracker on 2026-10-24:
- `CVE-2026-19499` (glibc 2.41-12+deb13u4): `strfmon`/`strfmon_l` can write past the output buffer with right-justified width padding. Debian marks trixie "no-dsa" (minor issue); fixed only in forky/sid (glibc 2.43-7). Needs application code that calls `strfmon`.
- `CVE-2026-5435` (same glibc): the deprecated resolver print functions (`ns_printrr` and relatives) do not honour the caller's buffer length. Debian: "no-dsa" (minor issue); fixed only in forky/sid.
- `CVE-2026-85091` (zlib `1.3.dfsg+really1.3.1-1`): heap overflow in `gzprintf` after a stalled non-blocking `gzwrite`. Debian lists trixie and bookworm as vulnerable with no fix yet. The CVE text gives the affected range as zlib 1.3.1.2 to 1.3.2, while the Debian package is built from 1.3.1, so the tracker entry and the description do not obviously agree; this was not resolved.

Reasoning: no fixed package exists for trixie or bookworm, so rebuilding or switching to another Debian-based Python image (3.11 or 3.12, slim) cannot remove these. All three need an application to call specific functions (`strfmon`, the resolver print functions, `gzprintf` on a non-blocking stream), and none of the four services is known to do so (the code was not searched for these calls). The services are not reachable from the internet except through API Gateway. Not covered: ECR basic scanning looks at operating-system packages only, not Python libraries. Actions: re-check the tracker at each rebuild; if Debian ships a fix, rebuild with `--pull` and record the new counts; before calling the project production-ready, consider ECR enhanced scanning (Inspector, which covers language packages and bills per image) and a pip dependency audit.

---

## Known risks and trade-offs

| Risk | Impact | Mitigation / plan |
|---|---|---|
| Practice mode (`allow_destroy = true`) | Destroy can remove stateful resources | Switch to `false` before treating anything as real; destroy only targeted modules |
| Single NAT gateway | One zone failure cuts outbound traffic for private subnets | `single_nat_gateway = false` for production |
| Single-AZ database | Outage if the zone fails; 1-day backups | Multi-AZ and longer backups for production |
| One task per service | No redundancy during deploys or failures | 2+ tasks per service for production |
| Internal ALB uses HTTP | Traffic inside the VPC is not encrypted | Acceptable inside private subnets for practice; add HTTPS and access logs for production |
| No WAF, no custom domain | Less protection, default domain only | O-10 |
| Image base vulnerabilities (3 HIGH, 9 MEDIUM, 3 LOW) | Come from Debian system libraries (glibc, zlib) in `python:3.11-slim`; Debian has no fix for trixie or bookworm. The `--pull` rebuild did not change the counts | Proposed: accept and re-check at every rebuild (D28). Python library vulnerabilities are not covered by the basic scan |
| Image tag points at a commit no longer on the branch | Traceability gap | Rebuild after final commit (O-3) |
| Budget only alerts | Money can still be spent | Destroy the paid stack after each session |
| `rds.force_ssl = 1` on the database (seen in the 2026-10-23 plan) | A client set to plain connections is refused | Python drivers normally prefer TLS, so this should work. If the user or order service cannot connect in the paid session, check the connection's SSL mode first |
| KMS-encrypted CloudWatch log groups (database, 2 groups) | Creation fails if the key policy does not allow the CloudWatch Logs service to use the key | Read the key policy in the `data` module before the paid session (open check, 2026-10-23) |

---

## Findings about the app code

**F-1. The services accept any token without verifying it.** They read the identity from the request but rely on the gateway to have checked the token. So the API Gateway JWT authorizer is the only gate, and a direct call to a service (bypassing the gateway) would not be protected. The ALB is internal for this reason. Test in the paid session: `curl -i <api>/cart` with no token must return 401.

**F-2 and F-3. Not recoverable.** The original text of these two findings was in the lost journal copy and the conversation summary kept only their numbers (they are referenced as "app-code fixes" in O-10). Re-review the services' authorization and input handling before calling the app production-ready.

**F-4. The services read their settings from SSM Parameter Store** under `/ecommerce/prod/` (list in runbook section 6.1). If a lookup fails they print a warning and fall back to localhost defaults, so a missing parameter looks like "service is up but can't reach anything". The IAM module already allows exactly these paths. The `ssm` module now creates them (commit `6becc1f`, decision D27).

**F-5. Readiness checks of the app code (2026-10-27).** All four services expose `GET /health` (`main.py` in each), which is the path the load balancer's target groups check. The user and order services create their own tables with `CREATE TABLE IF NOT EXISTS` in `database.py` (`users`; `orders` and `order_items`), so the empty PostgreSQL database needs no manual schema step, and `init_db()` is called from each service's `main.py` when the service starts (confirmed 2026-10-27), so a service started against a reachable empty database creates its own tables. The database is created with `rds.force_ssl = 1`; the connection code (`psycopg2.connect` in each `database.py`) sets no `sslmode`, and the default (`prefer`) tries TLS first, so it should connect (to be proven in the paid session). Failure signature to remember: if a service cannot reach the database at startup, `init_db()` fails and ECS restarts the task in a loop.
