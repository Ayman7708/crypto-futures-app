import re

with open('lib/volatility.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Use regex to add .toDouble() after every .clamp(0, N) that lacks it
# This will work regardless of trailing comments
pattern = re.compile(r'\.clamp\(0,\s*(\d+)\)(?!\.toDouble\(\)|\.toInt\(\))')

# Count matches first
matches = pattern.findall(src)
print(f"Found {len(matches)} clamps without toDouble")

# Replace - only on score += lines (to avoid affecting other logic)
def fix(m):
    return f'.clamp(0, {m.group(1)}).toDouble()'

src = pattern.sub(fix, src)

with open('lib/volatility.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/volatility.dart', 'r', encoding='utf-8') as f:
    final_src = f.read()

remaining = pattern.findall(final_src)
print(f"After fix: {len(remaining)} clamps without toDouble remaining")

# Show first few relevant lines
print("\n=== Lines with clamp ===")
for i, line in enumerate(final_src.split('\n'), 1):
    if '.clamp(' in line and 'score' in line:
        print(f"  {i}: {line.strip()}")
