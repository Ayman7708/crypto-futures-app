with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

print('=== تشخيص ===')
print(f'1. FALLBACK_SYMBOLS موجود: {"FALLBACK_SYMBOLS" in src}')
print(f'2. _activeSymbols معرف: {"List<String> get _activeSymbols" in src}')
print(f'3. _allSymbols موجود: {"_allSymbols" in src}')
print(f'4. _loadAllSymbols موجود: {"_loadAllSymbols" in src}')
print(f'5. SYMBOLS لا يزال مستخدم: {"SYMBOLS" in src.replace("FALLBACK_SYMBOLS", "").replace("_activeSymbols", "")}')

# Count occurrences
print(f'\nعدد مرات SYMBOLS (بعد استثناء FALLBACK): ', src.count('SYMBOLS') - src.count('FALLBACK_SYMBOLS'))
print(f'عدد مرات _activeSymbols: ', src.count('_activeSymbols'))

# List lines with SYMBOLS
print('\n=== أسطر تحتوي SYMBOLS ===')
for i, line in enumerate(src.split('\n'), 1):
    if 'SYMBOLS' in line and 'FALLBACK' not in line:
        print(f'  {i}: {line.strip()[:100]}')
