with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Add _loadAllSymbols method before _loadState
loader_method = """  Future<void> _loadAllSymbols() async {
    if (_loadingSymbols) return;
    setState(() => _loadingSymbols = true);
    try {
      final symbols = await MarketService.fetchAllSymbols(minVolumeUsdt: 50000000);
      if (symbols != null && symbols.isNotEmpty && mounted) {
        setState(() {
          _allSymbols = symbols;
          for (final s in symbols) {
            _priceHistory.putIfAbsent(s, () => []);
            _highHistory.putIfAbsent(s, () => []);
            _lowHistory.putIfAbsent(s, () => []);
            _volumeHistory.putIfAbsent(s, () => []);
          }
        });
        debugPrint('🎯 Loaded ${symbols.length} symbols from Binance');
      }
    } catch (e) {
      debugPrint('Failed to load symbols: $e');
    } finally {
      if (mounted) setState(() => _loadingSymbols = false);
    }
  }

"""
if 'Future<void> _loadAllSymbols' not in src:
    src = src.replace(
        "  Future<void> _loadState() async {",
        loader_method + "  Future<void> _loadState() async {",
        1,
    )
    checks.append(('loader method', 'Future<void> _loadAllSymbols' in src))
else:
    checks.append(('loader method', True))

# 2) Call _loadAllSymbols in initState
old_init = "    _loadState();\n    Timer(const Duration(seconds: 6), () {"
new_init = "    _loadState();\n    _loadAllSymbols();\n    Timer(const Duration(seconds: 6), () {"
if '_loadAllSymbols();' not in src and old_init in src:
    src = src.replace(old_init, new_init)
    checks.append(('call in init', '    _loadAllSymbols();' in src))
elif '    _loadAllSymbols();' in src:
    checks.append(('call in init', True))
else:
    checks.append(('call in init', False))

# 3) Add settings row for maxActiveSymbols
# Find the pattern `_settingRow('عدد العملات المُختارة'` and add before it
old_settings = "        _settingRow('عدد العملات المُختارة',"
new_settings = """        _settingRow('عدد العملات النشطة', '$_maxActiveSymbols',
            (v) => setState(() => _maxActiveSymbols = int.tryParse(v) ?? _maxActiveSymbols)),
        _settingRow('عدد العملات المُختارة',"""
if 'عدد العملات النشطة' not in src and old_settings in src:
    src = src.replace(old_settings, new_settings, 1)
    checks.append(('settings row', 'عدد العملات النشطة' in src))
elif 'عدد العملات النشطة' in src:
    checks.append(('settings row', True))
else:
    checks.append(('settings row', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Add Loader Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('========================')
