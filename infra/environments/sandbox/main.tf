locals {
  services = [
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "orgpolicy.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

module "baseline" {
  source = "../../modules/project-baseline"

  project_id                      = var.project_id
  project_number                  = var.project_number
  services                        = local.services
  billing_account                 = var.billing_account
  budget_amount                   = var.budget_amount
  enforce_no_service_account_keys = var.enforce_no_service_account_keys
}

# One identity per workload. None of them holds a project-level role.
module "api_sa" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "api-sa"
  display_name = "Upload API"
  description  = "Runs the API. Publishes to the uploads topic and reads the db-password secret, nothing else."

  depends_on = [module.baseline]
}

module "worker_sa" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "worker-sa"
  display_name = "Upload worker"
  description  = "Runs the worker. Creates objects in the results bucket, nothing else."

  depends_on = [module.baseline]
}

module "invoker_sa" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "pubsub-invoker"
  display_name = "Pub/Sub invoker"
  description  = "Identity of the OIDC token Pub/Sub sends. Holds run.invoker on the worker only."

  depends_on = [module.baseline]
}

module "db_password" {
  source = "../../modules/secret"

  project_id       = var.project_id
  secret_id        = "db-password"
  labels           = var.labels
  accessor_members = { api = module.api_sa.member }
  secret_data      = var.db_password

  depends_on = [module.baseline]
}

module "results" {
  source = "../../modules/results-bucket"

  project_id      = var.project_id
  name            = "${var.project_id}-results"
  location        = var.region
  labels          = var.labels
  creator_members = { worker = module.worker_sa.member }
  force_destroy   = true

  depends_on = [module.baseline]
}

module "registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  location      = var.region
  repository_id = "uploads"
  labels        = var.labels

  depends_on = [module.baseline]
}

module "worker" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  name                  = "worker"
  location              = var.region
  image                 = var.worker_image
  service_account_email = module.worker_sa.email
  labels                = var.labels
  env = {
    BUCKET     = module.results.name
    PROJECT_ID = var.project_id
  }
  invoker_members = { pubsub = module.invoker_sa.member }

  depends_on = [module.baseline]
}

module "pipeline" {
  source = "../../modules/pubsub-push"

  project_id                    = var.project_id
  project_number                = var.project_number
  topic_name                    = "uploads"
  push_endpoint                 = "${module.worker.uri}/"
  oidc_audience                 = module.worker.uri
  invoker_service_account_email = module.invoker_sa.email
  publisher_members             = { api = module.api_sa.member }
  labels                        = var.labels

  depends_on = [module.baseline]
}

module "api" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  name                  = "api"
  location              = var.region
  image                 = var.api_image
  service_account_email = module.api_sa.email
  labels                = var.labels
  env = {
    PROJECT_ID = var.project_id
    TOPIC_ID   = module.pipeline.topic_name
  }
  secret_env = {
    DB_PASSWORD = {
      secret  = module.db_password.secret_id
      version = "latest"
    }
  }
  invoker_members = var.api_public ? { public = "allUsers" } : {}

  depends_on = [module.baseline, module.db_password]
}
