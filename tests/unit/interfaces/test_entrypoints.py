import pytest

from uploads.infrastructure.settings import ConfigError
from uploads.interfaces import api_main, worker_main


def test_the_api_factory_builds_an_app_that_reports_the_secret_without_revealing_it(monkeypatch):
    monkeypatch.setenv("PUBSUB_EMULATOR_HOST", "localhost:1")
    monkeypatch.setenv("PROJECT_ID", "demo")
    monkeypatch.setenv("DB_PASSWORD", "not-shown")
    response = api_main.create().test_client().get("/health")
    assert response.get_json() == {"db_password_set": True}
    assert "not-shown" not in response.get_data(as_text=True)


def test_the_worker_factory_builds_an_app(monkeypatch):
    monkeypatch.setenv("STORAGE_EMULATOR_HOST", "http://localhost:1")
    monkeypatch.setenv("BUCKET", "demo-results")
    assert worker_main.create().test_client().get("/health").status_code == 200


def test_a_missing_setting_stops_startup_with_a_clear_message(monkeypatch):
    monkeypatch.delenv("BUCKET", raising=False)
    with pytest.raises(ConfigError, match="BUCKET is required"):
        worker_main.create()
