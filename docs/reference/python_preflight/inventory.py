"""
Repository Inventory System
===========================

Captures a complete snapshot of the repository state:
- Git branch, HEAD, working tree status
- Changed files with diffs
- File hashes for cache invalidation
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass
class FileChange:
    """Represents a single file change in the working tree."""
    path: str
    status: str  # A, M, D, R, ??, etc.
    old_path: str | None = None  # For renames
    staged: bool = False
    unstaged: bool = False
    hash: str | None = None  # Content hash for staged version


@dataclass
class RepositorySnapshot:
    """Complete snapshot of repository state at a point in time."""
    repo_root: Path
    branch: str
    head_commit: str
    head_message: str
    timestamp: datetime
    changes: list[FileChange] = field(default_factory=list)
    untracked_files: list[str] = field(default_factory=list)
    file_hashes: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "repo_root": str(self.repo_root),
            "branch": self.branch,
            "head_commit": self.head_commit,
            "head_message": self.head_message,
            "timestamp": self.timestamp.isoformat(),
            "changes": [
                {
                    "path": c.path,
                    "status": c.status,
                    "old_path": c.old_path,
                    "staged": c.staged,
                    "unstaged": c.unstaged,
                    "hash": c.hash,
                }
                for c in self.changes
            ],
            "untracked_files": self.untracked_files,
            "file_hashes": self.file_hashes,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> RepositorySnapshot:
        snapshot = cls(
            repo_root=Path(data["repo_root"]),
            branch=data["branch"],
            head_commit=data["head_commit"],
            head_message=data["head_message"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            untracked_files=data.get("untracked_files", []),
            file_hashes=data.get("file_hashes", {}),
        )
        snapshot.changes = [
            FileChange(
                path=c["path"],
                status=c["status"],
                old_path=c.get("old_path"),
                staged=c.get("staged", False),
                unstaged=c.get("unstaged", False),
                hash=c.get("hash"),
            )
            for c in data.get("changes", [])
        ]
        return snapshot


class RepositoryInventory:
    """Captures and manages repository state snapshots."""

    def __init__(self, repo_root: Path | None = None):
        self.repo_root = repo_root or Path.cwd()
        self._git_dir = self.repo_root / ".git"
        if not self._git_dir.exists():
            raise ValueError(f"Not a git repository: {self.repo_root}")

    def capture(self) -> RepositorySnapshot:
        """Capture current repository state."""
        branch = self._run_git("branch", "--show-current").strip()
        head_commit = self._run_git("rev-parse", "HEAD").strip()
        head_message = self._run_git("log", "-1", "--pretty=%B").strip()

        # Get staged changes
        staged_output = self._run_git("diff", "--cached", "--name-status")
        staged_changes = self._parse_name_status(staged_output, staged=True)

        # Get unstaged changes
        unstaged_output = self._run_git("diff", "--name-status")
        unstaged_changes = self._parse_name_status(unstaged_output, staged=False)

        # Merge staged and unstaged
        all_changes = self._merge_changes(staged_changes, unstaged_changes)

        # Get untracked files
        untracked_output = self._run_git("ls-files", "--others", "--exclude-standard")
        untracked = [f for f in untracked_output.strip().split("\n") if f]

        # Compute file hashes for staged files
        file_hashes = {}
        for change in all_changes:
            if change.staged:
                content = self._run_git("show", f":{change.path}")
                change.hash = hashlib.sha256(content.encode()).hexdigest()[:16]
                file_hashes[change.path] = change.hash

        return RepositorySnapshot(
            repo_root=self.repo_root,
            branch=branch,
            head_commit=head_commit,
            head_message=head_message,
            timestamp=datetime.now(),
            changes=all_changes,
            untracked_files=untracked,
            file_hashes=file_hashes,
        )

    def _run_git(self, *args: str) -> str:
        """Run a git command and return stdout."""
        result = subprocess.run(
            ["git", *args],
            cwd=self.repo_root,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr}")
        return result.stdout

    def _parse_name_status(self, output: str, staged: bool) -> list[FileChange]:
        """Parse git diff --name-status output."""
        changes = []
        for line in output.strip().split("\n"):
            if not line:
                continue
            parts = line.split("\t")
            status = parts[0]
            if status.startswith("R"):  # Rename
                old_path = parts[1]
                new_path = parts[2]
                changes.append(FileChange(
                    path=new_path,
                    status=status,
                    old_path=old_path,
                    staged=staged,
                ))
            else:
                path = parts[1]
                changes.append(FileChange(
                    path=path,
                    status=status,
                    staged=staged,
                ))
        return changes

    def _merge_changes(self, staged: list[FileChange], unstaged: list[FileChange]) -> list[FileChange]:
        """Merge staged and unstaged changes, deduplicating by path."""
        merged = {}
        for change in staged:
            merged[change.path] = change
        for change in unstaged:
            if change.path in merged:
                merged[change.path].unstaged = True
            else:
                merged[change.path] = change
        return list(merged.values())

    def get_changed_files(self, staged_only: bool = False) -> list[str]:
        """Get list of changed files."""
        snapshot = self.capture()
        if staged_only:
            return [c.path for c in snapshot.changes if c.staged]
        return [c.path for c in snapshot.changes]

    def get_staged_content_hash(self, path: str) -> str | None:
        """Get hash of staged content for a specific file."""
        try:
            content = self._run_git("show", f":{path}")
            return hashlib.sha256(content.encode()).hexdigest()[:16]
        except RuntimeError:
            return None

    def verify_staged_bytes(self, expected_hashes: dict[str, str]) -> tuple[bool, list[str]]:
        """Verify that staged bytes match expected hashes."""
        mismatches = []
        for path, expected_hash in expected_hashes.items():
            actual_hash = self.get_staged_content_hash(path)
            if actual_hash != expected_hash:
                mismatches.append(f"{path}: expected {expected_hash}, got {actual_hash}")
        return len(mismatches) == 0, mismatches


def load_snapshot(path: Path) -> RepositorySnapshot:
    """Load a snapshot from disk."""
    with open(path) as f:
        data = json.load(f)
    return RepositorySnapshot.from_dict(data)


def save_snapshot(snapshot: RepositorySnapshot, path: Path) -> None:
    """Save a snapshot to disk."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(snapshot.to_dict(), f, indent=2)