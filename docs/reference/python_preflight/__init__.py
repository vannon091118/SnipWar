"""
SnipWar Python Preflight CLI
============================

A standalone preflight verification system that runs without Godot for
static/structural gates, and delegates to Godot only for runtime/scene-specific gates.

Architecture: Git Snapshot → Inventory → Scope → Constraints → Evidence → Verdict → JSON/Report
"""

from __future__ import annotations

__version__ = "1.0.0"
__author__ = "SnipWar Team"

from .core import PreflightRunner
from .inventory import RepositoryInventory
from .constraints import ConstraintRegistry, ConstraintResult
from .scope import ScopeResolver
from .cache import FileCache
from .report import ReportGenerator

__all__ = [
    "PreflightRunner",
    "RepositoryInventory",
    "ConstraintRegistry",
    "ConstraintResult",
    "ScopeResolver",
    "FileCache",
    "ReportGenerator",
]