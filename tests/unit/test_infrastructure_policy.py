"""Guardrails over the Terraform source, checked without Terraform or Google Cloud.

These encode the lesson's rules as tests so a change that breaks one fails in CI: no keys, no project-level roles,
no broad roles, and public access only where it is asked for.
"""

import re
from pathlib import Path

import pytest

INFRA = Path(__file__).resolve().parents[2] / "infra"
SOURCES = {path: path.read_text() for path in INFRA.rglob("*.tf") if ".terraform" not in path.parts}
CODE = {path: re.sub(r"(?m)^\s*#.*$", "", text) for path, text in SOURCES.items()}


def _hits(pattern: str) -> list[str]:
    return [str(path.relative_to(INFRA)) for path, text in CODE.items() if re.search(pattern, text)]


def test_the_sources_were_found():
    assert len(SOURCES) >= 20


def test_no_service_account_key_is_ever_created():
    assert _hits(r'resource\s+"google_service_account_key"') == []


@pytest.mark.parametrize(
    "kind", ["google_project_iam_member", "google_project_iam_binding", "google_project_iam_policy"]
)
def test_no_project_level_role_is_granted(kind):
    assert _hits(rf'resource\s+"{kind}"') == []


@pytest.mark.parametrize(
    "role", ["roles/owner", "roles/editor", "roles/storage.admin", "roles/storage.objectAdmin", "roles/pubsub.admin"]
)
def test_no_broad_role_appears(role):
    assert _hits(re.escape(role)) == []


def test_all_authenticated_users_is_never_used():
    assert _hits("allAuthenticatedUsers") == []


def test_all_users_appears_only_in_the_sandbox_api_toggle():
    assert _hits('"allUsers"') == ["environments/sandbox/main.tf"]


def test_every_cloud_run_service_names_its_service_account():
    text = (INFRA / "modules/cloud-run-service/main.tf").read_text()
    assert "service_account = var.service_account_email" in text


def test_the_provider_is_pinned_in_every_root_and_module():
    for path in INFRA.rglob("versions.tf"):
        if ".terraform" in path.parts:
            continue
        assert re.search(r'version\s*=\s*"(~>|>=)\s*8', path.read_text()), path
