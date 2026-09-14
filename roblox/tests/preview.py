#!/usr/bin/env python3
"""يشغّل معاينة الفن بمُفسِّر Luau ويحوّل الأوراق إلى PNG لفحصها بالعين."""
import pathlib, subprocess, sys, zlib, struct
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import bundle

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
OUT = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else TESTS / "preview"
OUT.mkdir(parents=True, exist_ok=True)
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

combined = bundle.build().replace("return __req\n", "") + "\n" + (TESTS / "preview.luau").read_text(encoding="utf-8")
target = TESTS / ".preview.luau"
target.write_text(combined, encoding="utf-8")

result = subprocess.run([luau, str(target)], capture_output=True, text=True)
if result.returncode != 0:
    print(result.stderr[-3000:])
    sys.exit(1)

def write_png(path, width, height, rgba: bytes):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type 0
        raw += rgba[y * stride:(y + 1) * stride]
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)

lines = result.stdout.splitlines()
i = 0
names = {}
while i < len(lines):
    line = lines[i]
    if line.startswith("@NAMES "):
        _, sheet, rest = line.split(" ", 2)
        names[sheet] = rest
    elif line.startswith("@SHEET "):
        _, name, w, h = line.split()
        w, h = int(w), int(h)
        hexparts = []
        i += 1
        while i < len(lines) and lines[i] != "@END":
            hexparts.append(lines[i])
            i += 1
        data = bytes.fromhex("".join(hexparts))
        expected = w * h * 4
        assert len(data) == expected, f"{name}: {len(data)} != {expected}"
        write_png(OUT / f"{name}.png", w, h, data)
        print(f"كُتبت {name}.png  ({w}×{h})")
    i += 1

(OUT / "names.txt").write_text("\n\n".join(f"[{k}]\n{v}" for k, v in names.items()), encoding="utf-8")
print("أسماء العناصر في", OUT / "names.txt")
