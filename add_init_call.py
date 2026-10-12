with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Find initState body and add _loadAllSymbols() call
# Look for the `_loadState();` call inside initState and add _loadAllSymbols() after it
# (Only in initState, not in _loadState itself)

import re

# Find initState block
initstate_match = re.search(r'void initState\(\) \{.*?\n  \}', src, re.DOTALL)
if initstate_match:
    initstate = initstate_match.group(0)
    print("=== initState الحالي ===")
    print(initstate)
    print()
    
    if '_loadAllSymbols();' not in initstate:
        # Add call right after the first _loadState();
        if '_loadState();' in initstate:
            new_initstate = initstate.replace(
                '_loadState();',
                '_loadState();\n    _loadAllSymbols();',
                1
            )
            src = src.replace(initstate, new_initstate)
            checks.append(('added call', '_loadAllSymbols();' in new_initstate))
        else:
            checks.append(('added call', False))
    else:
        checks.append(('added call', True))
else:
    print("❌ initState غير موجود")
    checks.append(('initState found', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('\n=== Result ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
