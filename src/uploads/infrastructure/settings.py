"""Configuration from the environment (twelve-factor), validated once at startup."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field


class ConfigError(Exception):
    """One or more settings are missing or invalid; the message lists all of them."""


@dataclass(frozen=True, slots=True)
class Secret:
    """A secret value that never appears in a repr, a log line or a traceback."""

    _value: str = field(repr=False)

    def reveal(self) -> str:
        """The value; call only where it is used."""
        return self._value

    def __repr__(self) -> str:
        return "Secret(***)"

    def __str__(self) -> str:
        return "***"


@dataclass(frozen=True, slots=True)
class ApiSettings:
    """Settings of the API service."""

    project_id: str
    topic_id: str
    publish_timeout_seconds: float
    log_level: str
    db_password: Secret | None

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> ApiSettings:
        """Read `PROJECT_ID`, `TOPIC_ID`, `PUBLISH_TIMEOUT_SECONDS`, `LOG_LEVEL` and `DB_PASSWORD`."""
        problems: list[str] = []
        project_id = _required(env, "PROJECT_ID", problems)
        timeout = _positive_float(env, "PUBLISH_TIMEOUT_SECONDS", 10.0, problems)
        level = _log_level(env, problems)
        if problems:
            raise ConfigError("; ".join(problems))
        password = env.get("DB_PASSWORD")
        return cls(
            project_id=project_id,
            topic_id=env.get("TOPIC_ID", "uploads"),
            publish_timeout_seconds=timeout,
            log_level=level,
            db_password=Secret(password) if password else None,
        )


@dataclass(frozen=True, slots=True)
class WorkerSettings:
    """Settings of the worker service."""

    bucket: str
    project_id: str | None
    store_timeout_seconds: float
    log_level: str

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> WorkerSettings:
        """Read `BUCKET`, `PROJECT_ID` (optional), `STORE_TIMEOUT_SECONDS` and `LOG_LEVEL`."""
        problems: list[str] = []
        bucket = _required(env, "BUCKET", problems)
        timeout = _positive_float(env, "STORE_TIMEOUT_SECONDS", 30.0, problems)
        level = _log_level(env, problems)
        if problems:
            raise ConfigError("; ".join(problems))
        return cls(
            bucket=bucket,
            project_id=env.get("PROJECT_ID") or None,
            store_timeout_seconds=timeout,
            log_level=level,
        )


def _required(env: Mapping[str, str], name: str, problems: list[str]) -> str:
    value = env.get(name, "").strip()
    if not value:
        problems.append(f"{name} is required")
    return value


def _positive_float(env: Mapping[str, str], name: str, default: float, problems: list[str]) -> float:
    raw = env.get(name)
    if raw is None:
        return default
    try:
        value = float(raw)
    except ValueError:
        problems.append(f"{name} must be a number, got {raw!r}")
        return default
    if value <= 0:
        problems.append(f"{name} must be greater than zero, got {raw!r}")
        return default
    return value


def _log_level(env: Mapping[str, str], problems: list[str]) -> str:
    level = env.get("LOG_LEVEL", "INFO").upper()
    if level not in {"DEBUG", "INFO", "WARNING", "ERROR"}:
        problems.append(f"LOG_LEVEL must be DEBUG, INFO, WARNING or ERROR, got {level!r}")
    return level
