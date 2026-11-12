#!/usr/bin/env python3
"""Download the pinned toolchain into .tools/ (Linux x86_64 or macOS/Windows by
asset name). Idempotent: skips tools that are already present.

    python3 tools/setup_tools.py

Installs rojo, luau-lsp, the luau CLI (luau, luau-analyze, ...), lune and the
Roblox type definitions that luau-lsp needs (globalTypes.d.luau).
"""
import io
import os
import pathlib
import platform
import stat
import sys
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / ".tools"

ROJO = "7.7.1"
LUAU_LSP = "1.70.1"
LUAU = "0.746"
LUNE = "0.11.1"


def asset_names():
    system = platform.system()
    machine = platform.machine().lower()
    arm = machine in ("arm64", "aarch64")
    if system == "Linux":
        return {
            "rojo": f"rojo-{ROJO}-linux-{'aarch64' if arm else 'x86_64'}.zip",
            "luau-lsp": f"luau-lsp-linux-{'arm64' if arm else 'x86_64'}.zip",
            "luau": "luau-ubuntu.zip",
            "lune": f"lune-{LUNE}-linux-{'aarch64' if arm else 'x86_64'}.zip",
        }
    if system == "Darwin":
        return {
            "rojo": f"rojo-{ROJO}-macos-{'aarch64' if arm else 'x86_64'}.zip",
            "luau-lsp": "luau-lsp-macos.zip",
            "luau": "luau-macos.zip",
            "lune": f"lune-{LUNE}-macos-{'aarch64' if arm else 'x86_64'}.zip",
        }
    return {
        "rojo": f"rojo-{ROJO}-windows-x86_64.zip",
        "luau-lsp": "luau-lsp-win64.zip",
        "luau": "luau-windows.zip",
        "lune": f"lune-{LUNE}-windows-x86_64.zip",
    }


URLS = {
    "rojo": "https://github.com/rojo-rbx/rojo/releases/download/v{v}/{asset}",
    "luau-lsp": "https://github.com/JohnnyMorganz/luau-lsp/releases/download/{v}/{asset}",
    "luau": "https://github.com/luau-lang/luau/releases/download/{v}/{asset}",
    "lune": "https://github.com/lune-org/lune/releases/download/v{v}/{asset}",
}
VERSIONS = {"rojo": ROJO, "luau-lsp": LUAU_LSP, "luau": LUAU, "lune": LUNE}
TYPES_URL = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main() -> int:
    TOOLS.mkdir(exist_ok=True)
    exe = ".exe" if platform.system() == "Windows" else ""
    for tool, asset in asset_names().items():
        if (TOOLS / f"{tool}{exe}").exists():
            print(f"ok   {tool} (already installed)")
            continue
        url = URLS[tool].format(v=VERSIONS[tool], asset=asset)
        print(f"get  {tool} {VERSIONS[tool]}  {url}")
        with zipfile.ZipFile(io.BytesIO(fetch(url))) as archive:
            archive.extractall(TOOLS)
    for path in TOOLS.iterdir():
        if path.is_file() and not path.suffix:
            path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    types = TOOLS / "globalTypes.d.luau"
    if not types.exists():
        print(f"get  globalTypes.d.luau  {TYPES_URL}")
        types.write_bytes(fetch(TYPES_URL))
    print("toolchain ready in", os.path.relpath(TOOLS, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
