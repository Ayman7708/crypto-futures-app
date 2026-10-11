import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

before = len(src)

# 1) Remove protection state fields
patterns = [
    r"\n  double _dailyStartBalance = 0;",
    r"\n  DateTime _dailyStartDate = DateTime\.now\(\);",
    r"\n  int _dailyLossLimitPct = 10;",
    r"\n  bool _globalTrendFilter = true;",
    r"\n  int _maxConcurrentLosses = 3;",
]
for p in patterns:
    src = re.sub(p, "", src)

# 2) Remove daily reset block
reset_pattern = re.compile(
    r"        // Reset daily reference if new day.*?}\n        _loaded = true;",
    re.DOTALL
)
src = reset_pattern.sub("        _loaded = true;", src)

# 3) Remove _canOpen method entirely
canopen_pattern = re.compile(
    r"  bool _canOpen\(\) \{.*?\n  \}\n\n",
    re.DOTALL
)
src = canopen_pattern.sub("", src)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print(f"✅ Cleaned. Size: {before} -> {len(src)} chars")

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

leftovers = []
for name in ['_dailyStartBalance', '_dailyStartDate', '_dailyLossLimitPct',
             '_globalTrendFilter', '_maxConcurrentLosses', '_canOpen', 'Reset daily reference']:
    if name in final:
        leftovers.append(name)

if leftovers:
    print("⚠️ Still present:", leftovers)
else:
    print("🎉 All protection code removed successfully!")
