import pytest

from uploads.infrastructure.settings import ApiSettings, ConfigError, Secret, WorkerSettings


def test_api_settings_take_defaults_and_keep_the_password_secret():
    settings = ApiSettings.from_env({"PROJECT_ID": "demo-project", "DB_PASSWORD": "hunter2"})
    assert settings.topic_id == "uploads"
    assert settings.publish_timeout_seconds == 10.0
    assert settings.db_password is not None
    assert settings.db_password.reveal() == "hunter2"
    assert "hunter2" not in repr(settings)
    assert "hunter2" not in str(settings.db_password)


def test_api_settings_without_a_password_have_none():
    assert ApiSettings.from_env({"PROJECT_ID": "p", "DB_PASSWORD": ""}).db_password is None


def test_every_problem_is_reported_at_once():
    with pytest.raises(ConfigError) as caught:
        ApiSettings.from_env({"PUBLISH_TIMEOUT_SECONDS": "soon", "LOG_LEVEL": "LOUD"})
    message = str(caught.value)
    assert "PROJECT_ID is required" in message
    assert "PUBLISH_TIMEOUT_SECONDS must be a number" in message
    assert "LOG_LEVEL must be" in message


def test_a_timeout_of_zero_or_less_is_rejected():
    with pytest.raises(ConfigError, match="greater than zero"):
        WorkerSettings.from_env({"BUCKET": "b", "STORE_TIMEOUT_SECONDS": "0"})


def test_worker_settings_need_a_bucket_and_project_is_optional():
    with pytest.raises(ConfigError, match="BUCKET is required"):
        WorkerSettings.from_env({})
    settings = WorkerSettings.from_env({"BUCKET": "demo-results", "LOG_LEVEL": "debug"})
    assert (settings.bucket, settings.project_id, settings.log_level) == ("demo-results", None, "DEBUG")


def test_secret_repr_is_masked():
    assert repr(Secret("x")) == "Secret(***)"
