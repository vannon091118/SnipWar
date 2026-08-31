#!/bin/bash
# Build script for SnipWar - exports project for headless Linux/Windows
# Usage: ./scripts/build.sh [preset_name]
# If no preset specified, builds all headless presets

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
BUILD_DIR="${PROJECT_ROOT}/build"
PRESET="${1:-all}"

echo "=================================================="
echo " SnipWar Build Script"
echo "=================================================="
echo "Project: ${PROJECT_ROOT}"
echo "Godot:   ${GODOT_BIN}"
echo "Preset:  ${PRESET}"
echo "Output:  ${BUILD_DIR}"
echo "=================================================="

# Check Godot availability
if ! command -v "${GODOT_BIN}" &> /dev/null; then
    echo "[ERROR] Godot binary not found: ${GODOT_BIN}"
    echo "Set GODOT_BIN environment variable or add godot to PATH"
    exit 1
fi

# Verify Godot version
GODOT_VERSION=$("${GODOT_BIN}" --version 2>/dev/null | head -1)
echo "Godot Version: ${GODOT_VERSION}"

# Create build directory
mkdir -p "${BUILD_DIR}"

# Function to export a preset
export_preset() {
    local preset_name="$1"
    echo ""
    echo "--- Exporting preset: ${preset_name} ---"
    
    if "${GODOT_BIN}" --headless --path "${PROJECT_ROOT}" --export "${preset_name}" "${BUILD_DIR}/$(echo ${preset_name} | tr ' ' '_').exe" 2>&1; then
        echo "[SUCCESS] Export completed: ${preset_name}"
        return 0
    else
        echo "[FAILED] Export failed: ${preset_name}"
        return 1
    fi
}

# Function to run smoke test on exported binary
smoke_test() {
    local binary_path="$1"
    echo ""
    echo "--- Smoke testing: ${binary_path} ---"
    
    if [[ -f "${binary_path}" ]]; then
        if "${binary_path}" --headless --script res://scripts/testing/test_all.gd 2>&1; then
            echo "[SMOKE TEST PASSED] ${binary_path}"
            return 0
        else
            echo "[SMOKE TEST FAILED] ${binary_path}"
            return 1
        fi
    else
        echo "[SKIP] Binary not found: ${binary_path}"
        return 1
    fi
}

# Main build logic
case "${PRESET}" in
    "Linux Headless")
        export_preset "Linux Headless"
        smoke_test "${BUILD_DIR}/snipwar_linux_headless"
        ;;
    "Windows Headless")
        export_preset "Windows Headless"
        smoke_test "${BUILD_DIR}/snipwar_windows_headless.exe"
        ;;
    "Linux Release")
        export_preset "Linux Release"
        smoke_test "${BUILD_DIR}/snipwar_linux"
        ;;
    "Windows Release")
        export_preset "Windows Release"
        smoke_test "${BUILD_DIR}/snipwar_windows.exe"
        ;;
    "Web Release")
        export_preset "Web Release"
        ;;
    "all"|"headless")
        # Build headless presets by default
        export_preset "Linux Headless"
        export_preset "Windows Headless"
        
        # Smoke test if binaries exist
        smoke_test "${BUILD_DIR}/snipwar_linux_headless" || true
        smoke_test "${BUILD_DIR}/snipwar_windows_headless.exe" || true
        ;;
    *)
        echo "[ERROR] Unknown preset: ${PRESET}"
        echo "Available presets: Linux Headless, Windows Headless, Linux Release, Windows Release, Web Release, all, headless"
        exit 1
        ;;
esac

echo ""
echo "=================================================="
echo " Build completed!"
echo " Output directory: ${BUILD_DIR}"
ls -la "${BUILD_DIR}" 2>/dev/null || true
echo "=================================================="