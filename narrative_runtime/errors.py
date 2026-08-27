"""Errors raised by the narrative runtime and their CLI exit codes."""


class NarrativeRuntimeError(Exception):
    """Base error with a stable process exit code."""

    exit_code = 1


class ChainValidationError(NarrativeRuntimeError):
    """The source chain is malformed or contains a sequence gap."""

    exit_code = 3


class HistoryChangedError(NarrativeRuntimeError):
    """An imported chain rewrote history at or before the stored anchor."""

    exit_code = 2


class ImportAtomicityError(NarrativeRuntimeError):
    """An import failed and was rolled back."""

    exit_code = 1
