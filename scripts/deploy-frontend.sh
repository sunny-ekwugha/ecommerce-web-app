#!/usr/bin/env bash
# Builds the React app, uploads it to the frontend bucket and clears the CloudFront cache.
# Usage: bash scripts/deploy-frontend.sh [--dry-run]
#   --dry-run  builds, then only lists what the upload would copy or delete. Nothing in AWS changes.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash must not turn "/index.html" into a Windows path

DRY=""
if [ "${1:-}" = "--dry-run" ]; then DRY="--dryrun"; echo "DRY RUN: nothing will be changed in AWS."; fi

ROOT="$(git rev-parse --show-toplevel)"
APP="${ROOT}/frontend/react-app"

# 1. Write aws-config.js from Terraform outputs (stops here if the API is not applied yet).
bash "${ROOT}/scripts/configure-frontend.sh"

# 2. Read the bucket and distribution from Terraform.
cd "${ROOT}/terraform/envs/prod"
BUCKET="$(terraform output -raw frontend_bucket | tr -d '\r')"
DIST_ID="$(terraform output -raw cloudfront_id | tr -d '\r')"
DOMAIN="$(terraform output -raw cloudfront_domain | tr -d '\r')"
for v in BUCKET DIST_ID DOMAIN; do
  [ -n "${!v}" ] || { echo "ERROR: terraform output for ${v} is empty." >&2; exit 1; }
done

# 3. Build.
cd "${APP}"
if [ -n "${SKIP_INSTALL:-}" ]; then echo "SKIP_INSTALL set: reusing node_modules"; elif [ -f package-lock.json ]; then npm ci; else npm install; fi
npm run build
[ -f build/index.html ] || { echo "ERROR: build/index.html was not produced." >&2; exit 1; }

# 4. Remember how many product images exist; the upload must never change that.
count_images() { aws s3 ls "s3://${BUCKET}/images/products/" | wc -l | tr -d ' '; }
BEFORE="$(count_images)"
echo "Product images in bucket before: ${BEFORE}"

# 5. Upload. Hashed files under static/ never change, so they cache for a year and old ones are kept
#    (a visitor with an older page still needs them). Everything else is revalidated every time.
#    --exclude "images/*" also protects the bucket's images/ folder from --delete.
aws s3 sync build/static "s3://${BUCKET}/static" ${DRY} \
  --cache-control "public,max-age=31536000,immutable"
aws s3 sync build "s3://${BUCKET}" ${DRY} --delete \
  --exclude "static/*" --exclude "images/*" \
  --cache-control "no-cache"

# 6. Verify the images are untouched, then clear the cached page.
AFTER="$(count_images)"
echo "Product images in bucket after: ${AFTER}"
[ "${BEFORE}" = "${AFTER}" ] || { echo "ERROR: product image count changed (${BEFORE} -> ${AFTER})." >&2; exit 1; }

if [ -z "${DRY}" ]; then
  aws cloudfront create-invalidation --distribution-id "${DIST_ID}" --paths "/index.html" \
    --query 'Invalidation.{Id:Id,Status:Status}' --output table
fi

echo "Done. Site: https://${DOMAIN}"