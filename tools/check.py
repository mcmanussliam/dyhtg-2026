#!/usr/bin/env python3
"""Format/lint, import, run physics regressions, and boot the native Godot project."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    try:
        result = subprocess.run(
            command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=120, env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"},
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        print(output.decode(errors="replace") if isinstance(output, bytes) else output, end="")
        raise SystemExit(f"Check timed out after 120 seconds: {' '.join(command)}") from None
    print(result.stdout, end="", flush=True)
    errors = any(line.startswith(("ERROR:", "SCRIPT ERROR:"))
                 for line in result.stdout.splitlines())
    if result.returncode or errors:
        raise SystemExit(result.returncode or 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if not binary:
        parser.error("Pass --godot /path/to/Godot")
    binary = str(Path(binary).resolve())
    version = (ROOT / ".godot-version").read_text().strip()
    found = subprocess.check_output([binary, "--version"], text=True).strip()
    if not found.startswith(version + ".stable"):
        parser.error(f"Use Godot {version} Standard; found {found}")
    run([sys.executable, "-m", "gdtoolkit.formatter", "--check", "game", "tests"])
    run([sys.executable, "-m", "gdtoolkit.linter", "game", "tests"])
    prefix = [binary, "--headless", "--path", str(ROOT)]
    run(prefix + ["--editor", "--import", "--quit"])
    # Parse failures can leave an engine runner alive without executing its quit().
    for script in ["res://tests/run_tests.gd", "res://tests/run_match_tests.gd"]:
        run(prefix + ["--check-only", "--script", script])
    run(prefix + ["--fixed-fps", "60", "--script", "res://tests/run_tests.gd"])
    run(prefix + ["--fixed-fps", "60", "--script", "res://tests/run_match_tests.gd"])
    run(prefix + ["--quit-after", "5"])
    print("All checks passed.")


if __name__ == "__main__":
    main()
