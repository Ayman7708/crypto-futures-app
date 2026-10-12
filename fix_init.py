with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Use exact text from initState
old = """    _loadState().then((_) {
      if (mounted && !_running) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_running) _toggleBot();
        });
      }
    });"""

new = """    _loadAllSymbols();
    _loadState().then((_) {
      if (mounted && !_running) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_running) _toggleBot();
        });
      }
    });"""

if '_loadAllSymbols();' in src:
    print('✅ Already added')
elif old in src:
    src = src.replace(old, new, 1)
    print('✅ Added _loadAllSymbols() call in initState')
else:
    print('❌ Pattern not found. Showing first 20 lines of initState:')
    import re
    m = re.search(r'void initState\(\) \{.*?\n  \}', src, re.DOTALL)
    if m:
        for i, line in enumerate(m.group(0).split('\n')[:25], 1):
            print(f'  {i}: {line}')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

# Check if call exists in initState
import re
init_match = re.search(r'void initState\(\) \{.*?\n  \}', final, re.DOTALL)
# Use more robust detection
init_idx = final.find('void initState()')
if init_idx > 0:
    # Find matching closing brace
    brace_count = 0
    started = False
    end_idx = init_idx
    for i in range(init_idx, min(init_idx + 3000, len(final))):
        if final[i] == '{':
            brace_count += 1
            started = True
        elif final[i] == '}':
            brace_count -= 1
            if started and brace_count == 0:
                end_idx = i
                break
    init_body = final[init_idx:end_idx]
    if '_loadAllSymbols();' in init_body:
        print('✅ Verified: _loadAllSymbols() in initState')
    else:
        print('⚠️ Not found in initState body')
