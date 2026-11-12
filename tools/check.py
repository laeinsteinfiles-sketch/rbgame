#!/usr/bin/env python3
"""One-command verification: strict type-check, pure-module self tests, and a
fresh place build.

    python3 tools/check.py            # analyze + selftest + build
    python3 tools/check.py --no-build

Requires the toolchain from `python3 tools/setup_tools.py`.
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / ".tools"


def run(label: str, cmd: list[str]) -> int:
    print(f"== {label}")
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    # luau-lsp prints informational lines; keep only diagnostics and failures.
    lines = [
        line
        for line in output.splitlines()
        if not line.startswith("[INFO]") and "didChangeWatchedFiles" not in line
    ]
    if lines:
        print("\n".join(lines))
    if result.returncode != 0:
        print(f"!! {label} failed (exit {result.returncode})")
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()

    failures = 0
    failures += run("rojo sourcemap", [str(TOOLS / "rojo"), "sourcemap", "default.project.json", "-o", "sourcemap.json"]) != 0
    failures += run(
        "luau-lsp analyze (strict)",
        [
            str(TOOLS / "luau-lsp"),
            "analyze",
            "--sourcemap=sourcemap.json",
            f"--definitions={TOOLS / 'globalTypes.d.luau'}",
            "--base-luaurc=.luaurc",
            "--ignore=**/Packages/**",
            "src",
            "tools/EconomySim.luau",
        ],
    ) != 0
    failures += run("selftest", [sys.executable, str(ROOT / "tools" / "selftest.py")]) != 0
    if not args.no_build:
        failures += run(
            "rojo build",
            [str(TOOLS / "rojo"), "build", "default.project.json", "-o", "build/DigToTheCore.rbxl"],
        ) != 0
    print("ALL CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
