"""
Preflight CLI Entry Point
=========================

Main entry point for python -m preflight
"""

from .core import main

if __name__ == "__main__":
    import sys
    sys.exit(main())