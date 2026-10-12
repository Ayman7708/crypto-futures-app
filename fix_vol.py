with open('lib/volatility.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Fix clamp returning num instead of double
src = src.replace(
    "final opp = score.clamp(0, 100);",
    "final opp = score.clamp(0, 100).toDouble();"
)

# Also fix any other clamps that return num
src = src.replace(
    "final score += (atrPct * 8).clamp(0, 40);",
    "score += (atrPct * 8).clamp(0, 40).toDouble();"
)
src = src.replace(
    "score += ((vs - 1) * 15).clamp(0, 25);",
    "score += ((vs - 1) * 15).clamp(0, 25).toDouble();"
)
src = src.replace(
    "score += (momentum.abs() * 2).clamp(0, 20);",
    "score += (momentum.abs() * 2).clamp(0, 20).toDouble();"
)
src = src.replace(
    "score += (rangePct * 1.2).clamp(0, 15);",
    "score += (rangePct * 1.2).clamp(0, 15).toDouble();"
)

with open('lib/volatility.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/volatility.dart', 'r', encoding='utf-8') as f:
    final_src = f.read()

checks = []
if '.clamp(0, 100).toDouble()' in final_src:
    checks.append(('opp clamp fixed', True))
else:
    checks.append(('opp clamp fixed', False))

if 'score += (atrPct * 8).clamp(0, 40).toDouble()' in final_src:
    checks.append(('score clamps fixed', True))
else:
    checks.append(('score clamps fixed', False))

print('=== Fix Volatility ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
