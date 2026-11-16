"""Application configuration.

All runtime state lives inside a single data directory so that backups are
predictable and user books never mix with source code.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def default_data_dir() -> Path:
    override = os.environ.get("GUWEN_DATA_DIR")
    if override:
        return Path(override).expanduser().resolve()
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")
        return base / "古文阅读器"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "古文阅读器"
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    return base / "古文阅读器"


class Settings(BaseSettings):
    """Runtime settings, overridable with GUWEN_* environment variables."""

    model_config = SettingsConfigDict(env_prefix="GUWEN_", env_file=".env", extra="ignore")

    app_name: str = "古文阅读器"
    version: str = "0.1.0"
    env: Literal["development", "production", "test"] = "development"
    mode: Literal["embedded", "server"] = "embedded"
    host: str = "127.0.0.1"
    port: int = 8765

    data_dir: Path = Field(default_factory=default_data_dir)
    database_url: str | None = None
    auto_create_schema: bool = True

    # Secrets are never logged and never returned by the API.
    secret_key: str | None = None
    auth_secret: str | None = None
    token_ttl_hours: int = 24 * 30
    require_auth: bool = False
    cors_origins: str = "*"

    log_level: str = "INFO"
    log_json: bool = False

    max_upload_mb: int = 512
    translation_batch_chars: int = 2200
    translation_context_chars: int = 1000
    translation_temperature: float = 0.2
    translation_max_retries: int = 3
    task_workers: int = 1

    # Optional network sync; off by default in embedded mode.
    sync_enabled: bool = False
    server_public_url: str | None = None

    @model_validator(mode="after")
    def _fill_derived(self) -> "Settings":
        self.data_dir = self.data_dir.expanduser().resolve()
        if not self.database_url:
            db_file = (self.data_dir / "guwen.db").as_posix()
            self.database_url = f"sqlite+aiosqlite:///{db_file}"
        if self.mode == "server" and not self.require_auth:
            # Server deployments must authenticate unless explicitly disabled.
            self.require_auth = True
        return self

    # ------------------------------------------------------------------ paths
    @property
    def books_dir(self) -> Path:
        return self.data_dir / "books"

    @property
    def covers_dir(self) -> Path:
        return self.data_dir / "covers"

    @property
    def cache_dir(self) -> Path:
        return self.data_dir / "cache"

    @property
    def logs_dir(self) -> Path:
        return self.data_dir / "logs"

    @property
    def backups_dir(self) -> Path:
        return self.data_dir / "backups"

    @property
    def tmp_dir(self) -> Path:
        return self.data_dir / "tmp"

    @property
    def prompts_dir(self) -> Path:
        return Path(__file__).resolve().parent.parent / "resources" / "prompts"

    @property
    def resources_dir(self) -> Path:
        return Path(__file__).resolve().parent.parent / "resources"

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]

    @property
    def auth_required(self) -> bool:
        return self.require_auth or self.mode == "server"

    def ensure_directories(self) -> None:
        for path in (
            self.data_dir,
            self.books_dir,
            self.covers_dir,
            self.cache_dir,
            self.logs_dir,
            self.backups_dir,
            self.tmp_dir,
        ):
            path.mkdir(parents=True, exist_ok=True)
