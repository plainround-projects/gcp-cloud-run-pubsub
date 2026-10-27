# Artifact Registry

## 1. What it is

Artifact Registry is Google Cloud's store for build outputs. This repository uses it as a **Docker (container image) registry**: a server where images are pushed and from which Cloud Run pulls them. An image has a name like `europe-west1-docker.pkg.dev/PROJECT/uploads/api:TAG`: region, project, repository, image, tag.

## 2. Why this repository uses it

Cloud Run needs to fetch images from somewhere. A repository inside the same project, with immutable tags, keeps the lesson self-contained.

## 3. Where it appears

| Path | What it does with Artifact Registry |
| --- | --- |
| `infra/modules/artifact-registry/main.tf` | Creates the `uploads` repository with immutable tags and cleanup rules. |
| `scripts/build-images.sh` | Builds for `linux/amd64`, pushes `api` and `worker` with a unique timestamp tag, and writes the names where Terraform reads them. |
| `scripts/deploy.sh` | Applies Terraform twice: first with a placeholder image, then with yours. |
| `infra/environments/sandbox/variables.tf` | `api_image` and `worker_image` default to Google's public hello image. |

## 4. How it works underneath

- Pushing an image uploads **layers** (the pieces of the image) and a **manifest** that lists them. A **tag** (`:20261027120000`) is a label pointing at one manifest. **Immutable tags** forbid moving a tag to a new image, so a tag always means the same bytes. That is why each push uses a new timestamp tag.
- Docker needs credentials to push. `gcloud auth configure-docker REGION-docker.pkg.dev` adds a **credential helper** to Docker's config so it asks `gcloud` for a token. No password is stored.
- A **cleanup policy** deletes old versions automatically.
- Because the first Terraform apply must create the repository *before* any image exists, the services start with a public placeholder image and are updated in the second apply.

## 5. Walkthrough of this repository's use

`infra/modules/artifact-registry/main.tf`

```hcl
resource "google_artifact_registry_repository" "this" {
  #checkov:skip=CKV_GCP_84:Google-managed encryption is the default and enough here; customer-managed keys are the subject of the gke-identity-and-keys project
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Container images for the upload API and worker."
  labels        = var.labels

  docker_config {
    immutable_tags = true
  }
```

- `format = "DOCKER"` makes it an image registry.
- `docker_config { immutable_tags = true }` blocks re-pointing tags.
- `cleanup_policies` with `KEEP most_recent_versions { keep_count }` and `DELETE older_than = "2592000s"` (30 days): the newest five versions are always kept; older ones go.
- The `#checkov:skip` comment records a reviewed exception: Google-managed encryption is enough here.

The script that pushes:

`scripts/build-images.sh`

```bash
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
```

- `date -u +%Y%m%d%H%M%S` makes a unique tag in UTC.
- `docker build --platform linux/amd64 --target "$target" -t ...` builds one Dockerfile target for the processor type Cloud Run uses, even on an Apple-silicon Mac.
- `docker push` uploads. The heredoc (`<<VARS ... VARS`) writes `images.auto.tfvars`; Terraform loads any file ending in `.auto.tfvars` by itself.

## 6. Try it yourself

```bash
cd infra/modules/artifact-registry && terraform init -backend=false -input=false >/dev/null && terraform validate
```
Expected: `Success! The configuration is valid.`

```bash
shellcheck scripts/build-images.sh && echo clean
```
Expected: `clean`.

```bash
grep -n "immutable_tags\|keep_count\|older_than" infra/modules/artifact-registry/*.tf
```
Expected: the three settings above.

## 7. Mistakes people make

- **Reusing a tag** (`:latest`). With immutable tags the push is refused; without them Cloud Run may run stale code.
- **Building for the wrong CPU.** An Apple-silicon build runs nowhere on Cloud Run; use `--platform linux/amd64`.
- **Forgetting `configure-docker`.** Pushes fail with an authentication error.
- **Deploying before the image exists.** Hence the placeholder first pass.

## 8. Check yourself

1. What does an immutable tag guarantee? *A tag always points at the same image.*
2. What does `configure-docker` do? *Adds a Docker credential helper that uses `gcloud` tokens.*
3. Why is the first apply done with a placeholder image? *The repository does not hold your image until after that apply.*
4. How many recent versions are always kept here? *Five.*
5. What does `--platform linux/amd64` change? *Builds for the CPU architecture Cloud Run runs.*

## 9. Further reading

- Artifact Registry: <https://cloud.google.com/artifact-registry/docs>
- Docker authentication: <https://cloud.google.com/artifact-registry/docs/docker/authentication>
- Cleanup policies: <https://cloud.google.com/artifact-registry/docs/repositories/cleanup-policy>
