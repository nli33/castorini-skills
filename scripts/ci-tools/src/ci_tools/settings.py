"""CI environment settings."""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class CISettings(BaseSettings):
    """Settings loaded from environment variables and optional local .env files."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    github_token: str = ""
    github_repository: str = ""
    github_sha: str = ""
    ci: bool = False
