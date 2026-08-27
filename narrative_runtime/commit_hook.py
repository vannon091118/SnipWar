"""Best-effort post-push runtime synchronization.

This module is deliberately callable by external orchestration, but has no Git
writes and returns a structured anomaly report instead of raising into DOKI.
"""

from __future__ import annotations

from typing import Any

from .errors import NarrativeRuntimeError
from .observe import SourceSnapshot
from .store import Archive


def synchronize(archive: Archive, snapshot: SourceSnapshot) -> dict[str, Any]:
    """Import the current snapshot and report anomalies without blocking callers."""
    try:
        result = archive.import_snapshot(snapshot)
        verified = archive.verify(snapshot)
        return {"ok": verified, "anomaly": None if verified else "VERIFY_FAILED", **result}
    except NarrativeRuntimeError as exc:
        return {"ok": False, "anomaly": type(exc).__name__, "reason": str(exc), "exit_code": exc.exit_code}
    except Exception as exc:  # best-effort boundary: DOKI/Git must remain unaffected
        return {"ok": False, "anomaly": type(exc).__name__, "reason": str(exc), "exit_code": 1}
