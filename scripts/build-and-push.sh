#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-1}"
PREFIX="ecommerce-prod"
SERVICES=(product-service cart-service order-service user-service)

cd "$(git rev-parse --show-toplevel)"

if ! git diff --quiet -- services || ! git diff --cached --quiet -- services; then
  echo "ERROR: uncommitted changes in services/. Commit them first so the image tag matches the code." >&2
  exit 1
fi

TAG="$(git rev-parse --short=12 HEAD)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "Registry: ${REGISTRY}   Tag: ${TAG}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

for SVC in "${SERVICES[@]}"; do
  IMAGE="${REGISTRY}/${PREFIX}/${SVC}:${TAG}"
  echo "==> ${SVC}"
  if aws ecr describe-images --region "${REGION}" --repository-name "${PREFIX}/${SVC}" --image-ids imageTag="${TAG}" >/dev/null 2>&1; then
    echo "    tag ${TAG} already in ECR, skipping (tags are immutable)"
    continue
  fi
  docker build --pull --platform linux/amd64 -t "${IMAGE}" "services/${SVC}"
  docker push "${IMAGE}"
done

echo "Done. Image tag: ${TAG}"