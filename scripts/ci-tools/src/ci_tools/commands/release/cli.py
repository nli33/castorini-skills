"""Typer sub-app for release commands."""
from __future__ import annotations

import typer

release_app = typer.Typer(
    name="release",
    help="Release management commands.",
    no_args_is_help=True,
)
