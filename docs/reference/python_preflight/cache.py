"""
File Cache System
=================

Provides content-addressable caching for file hashes and parsed results.
Ensures deterministic results for identical repository snapshots.
"""

from __future__ import annotations

import hashlib
import json
import os
import pickle
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class CacheEntry:
    """A single cache entry with metadata."""
    key: str
    value: Any
    created_at: float = field(default_factory=time.time)
    file_hashes: dict[str, str] = field(default_factory=dict)
    version: int = 1

    def is_valid(self, current_hashes: dict[str, str]) -> bool:
        """Check if cache entry is still valid for current file state."""
        for file_path, expected_hash in self.file_hashes.items():
            if current_hashes.get(file_path) != expected_hash:
                return False
        return True


class FileCache:
    """Content-addressable file cache with automatic invalidation."""

    def __init__(self, cache_dir: Path | None = None, max_size_mb: int = 100):
        self.cache_dir = cache_dir or Path.home() / ".cache" / "snipwar_preflight"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.max_size_bytes = max_size_mb * 1024 * 1024
        self._memory_cache: dict[str, CacheEntry] = {}
        self._load_index()

    def _load_index(self) -> None:
        """Load cache index from disk."""
        index_path = self.cache_dir / "index.json"
        if index_path.exists():
            try:
                with open(index_path) as f:
                    data = json.load(f)
                for key, entry_data in data.items():
                    self._memory_cache[key] = CacheEntry(**entry_data)
            except (json.JSONDecodeError, TypeError):
                # Corrupted index, start fresh
                self._memory_cache.clear()

    def _save_index(self) -> None:
        """Save cache index to disk."""
        index_path = self.cache_dir / "index.json"
        data = {
            key: {
                "key": entry.key,
                "value": entry.value,
                "created_at": entry.created_at,
                "file_hashes": entry.file_hashes,
                "version": entry.version,
            }
            for key, entry in self._memory_cache.items()
        }
        with open(index_path, "w") as f:
            json.dump(data, f)

    def _get_cache_path(self, key: str) -> Path:
        """Get filesystem path for a cache key."""
        # Use hash of key as filename to avoid filesystem issues
        hashed = hashlib.sha256(key.encode()).hexdigest()[:32]
        return self.cache_dir / f"{hashed}.cache"

    def get(self, key: str, file_hashes: dict[str, str] | None = None) -> Any | None:
        """Get cached value if valid."""
        entry = self._memory_cache.get(key)
        if entry is None:
            return None

        if file_hashes and not entry.is_valid(file_hashes):
            # Invalidate stale entry
            self._remove_entry(key)
            return None

        return entry.value

    def set(self, key: str, value: Any, file_hashes: dict[str, str] | None = None) -> None:
        """Store value in cache."""
        entry = CacheEntry(
            key=key,
            value=value,
            file_hashes=file_hashes or {},
        )
        self._memory_cache[key] = entry
        self._save_index()
        self._enforce_size_limit()

    def _remove_entry(self, key: str) -> None:
        """Remove a cache entry."""
        if key in self._memory_cache:
            del self._memory_cache[key]
            cache_path = self._get_cache_path(key)
            if cache_path.exists():
                cache_path.unlink()

    def _enforce_size_limit(self) -> None:
        """Remove oldest entries if cache exceeds size limit."""
        total_size = sum(
            self._get_cache_path(key).stat().st_size
            for key in self._memory_cache
            if self._get_cache_path(key).exists()
        )

        if total_size > self.max_size_bytes:
            # Sort by creation time, remove oldest
            sorted_keys = sorted(
                self._memory_cache.keys(),
                key=lambda k: self._memory_cache[k].created_at
            )
            for key in sorted_keys:
                if total_size <= self.max_size_bytes * 0.8:  # Remove to 80%
                    break
                cache_path = self._get_cache_path(key)
                if cache_path.exists():
                    total_size -= cache_path.stat().st_size
                self._remove_entry(key)
            self._save_index()

    def clear(self) -> None:
        """Clear all cache entries."""
        for key in list(self._memory_cache.keys()):
            self._remove_entry(key)
        self._save_index()

    def get_file_hash(self, file_path: Path) -> str:
        """Get SHA256 hash of a file (first 16 chars)."""
        if not file_path.exists():
            return ""
        hasher = hashlib.sha256()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hasher.update(chunk)
        return hasher.hexdigest()[:16]

    def get_file_hashes(self, paths: list[Path]) -> dict[str, str]:
        """Get hashes for multiple files."""
        return {str(p): self.get_file_hash(p) for p in paths if p.exists()}

    def cache_parsed_result(self, file_path: Path, result: Any) -> None:
        """Cache a parsed result (e.g., AST, regex matches)."""
        file_hash = self.get_file_hash(file_path)
        key = f"parsed:{file_path}:{file_hash}"
        self.set(key, result, {str(file_path): file_hash})

    def get_parsed_result(self, file_path: Path) -> Any | None:
        """Get cached parsed result if file unchanged."""
        file_hash = self.get_file_hash(file_path)
        key = f"parsed:{file_path}:{file_hash}"
        return self.get(key, {str(file_path): file_hash})


class ConstraintCache:
    """Specialized cache for constraint results."""

    def __init__(self, file_cache: FileCache):
        self.file_cache = file_cache

    def get_constraint_result(self, constraint_id: str, snapshot_hash: str) -> Any | None:
        """Get cached constraint result."""
        key = f"constraint:{constraint_id}:{snapshot_hash}"
        return self.file_cache.get(key)

    def set_constraint_result(self, constraint_id: str, snapshot_hash: str, result: Any) -> None:
        """Cache constraint result."""
        key = f"constraint:{constraint_id}:{snapshot_hash}"
        self.file_cache.set(key, result)

    def get_snapshot_hash(self, snapshot: "RepositorySnapshot") -> str:
        """Generate deterministic hash for a repository snapshot."""
        import hashlib
        hasher = hashlib.sha256()
        hasher.update(snapshot.head_commit.encode())
        hasher.update(snapshot.branch.encode())
        # Include hashes of all changed files
        for change in sorted(snapshot.changes, key=lambda c: c.path):
            if change.hash:
                hasher.update(change.path.encode())
                hasher.update(change.hash.encode())
        return hasher.hexdigest()[:32]


# Forward reference
from .inventory import RepositorySnapshot