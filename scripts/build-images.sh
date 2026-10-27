#!/usr/bin/env bash
# Build both images for linux/amd64 (Cloud Run's platform, also on an Apple-silicon Mac), push them to Artifact Registry
# and write the image names where Terraform reads them. Tags are unique because the repository's tags are immutable.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

PREFIX="$REGION-docker.pkg.dev/$PROJECT_ID/uploads"
TAG="$(date -u +%Y%m%d%H%M%S)"

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
for target in api worker; do
  docker build --platform linux/amd64 --target "$target" -t "$PREFIX/$target:$TAG" "$ROOT"
  docker push "$PREFIX/$target:$TAG"
done

cat >"$ENV_DIR/images.auto.tfvars" <<VARS
api_image    = "$PREFIX/api:$TAG"
worker_image = "$PREFIX/worker:$TAG"
VARS
echo "wrote $ENV_DIR/images.auto.tfvars"
