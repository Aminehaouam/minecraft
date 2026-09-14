#!/usr/bin/env python3
"""يبني الحزمة ثم يشغّل الاختبارات بمُفسِّر Luau."""
import pathlib, subprocess, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import bundle

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

combined = bundle.build().replace("return __req\n", "") + "\n" + (TESTS / "spec.luau").read_text(encoding="utf-8")
target = TESTS / ".run.luau"
target.write_text(combined, encoding="utf-8")

result = subprocess.run([luau, str(target)])
sys.exit(result.returncode)
