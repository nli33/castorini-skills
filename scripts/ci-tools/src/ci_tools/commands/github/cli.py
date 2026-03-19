"""Typer sub-app for GitHub commands."""
from __future__ import annotations

import typer

github_app = typer.Typer(
    name="github",
    help="GitHub repository management commands.",
    no_args_is_help=True,
)
