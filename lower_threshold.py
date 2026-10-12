with open('lib/engine.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Lower LONG threshold from 60 to 50
src = src.replace('if (score >= 60) {\n        final sl = price - atr * 1.5;',
                  'if (score >= 50) {\n        final sl = price - atr * 1.5;')
# Lower SHORT threshold from 60 to 50
src = src.replace('if (score >= 60) {\n        final sl = price + atr * 1.5;',
                  'if (score >= 50) {\n        final sl = price + atr * 1.5;')

with open('lib/engine.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/engine.dart', 'r', encoding='utf-8') as f:
    final = f.read()

import re
hits = re.findall(r'if \(score >= (\d+)\)', final)
print(f"✅ Thresholds found: {hits}")
