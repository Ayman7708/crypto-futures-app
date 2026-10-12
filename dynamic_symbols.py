with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) import
if "import 'market_symbols.dart';" not in src:
    src = src.replace(
        "import 'volatility.dart';",
        "import 'volatility.dart';\nimport 'market_symbols.dart';"
    )
checks.append(('import', "import 'market_symbols.dart';" in src))

# 2) Replace const SYMBOLS with a fallback + dynamic state
old_symbols_block = """const List<String> SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT',
  'ADAUSDT', 'DOTUSDT', 'LINKUSDT', 'MATICUSDT', 'AVAXUSDT', 'ATOMUSDT',
  'NEARUSDT', 'FILUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT', 'INJUSDT',
  'SUIUSDT', 'LTCUSDT',
];"""

new_symbols_block = """// Fallback list used until Binance fetch completes
const List<String> FALLBACK_SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT',
  'ADAUSDT', 'DOTUSDT', 'LINKUSDT', 'MATICUSDT', 'AVAXUSDT', 'ATOMUSDT',
  'NEARUSDT', 'FILUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT', 'INJUSDT',
  'SUIUSDT', 'LTCUSDT',
];"""

if old_symbols_block in src:
    src = src.replace(old_symbols_block, new_symbols_block)
    checks.append(('fallback symbols', 'FALLBACK_SYMBOLS' in src))
else:
    checks.append(('fallback symbols', False))

# 3) Replace all references to SYMBOLS with _activeSymbols getter (except FALLBACK)
# First, add state field and getter
state_target = "  final Map<String, VolatilityScore> _volScores = {};"
new_state = """  final Map<String, VolatilityScore> _volScores = {};
  List<String> _allSymbols = [];
  int _maxActiveSymbols = 30;
  bool _loadingSymbols = false;

  List<String> get _activeSymbols {
    if (_allSymbols.isEmpty) return FALLBACK_SYMBOLS;
    // If we have volatility scores, return top N by opportunity
    if (_volScores.isNotEmpty) {
      final sorted = _volScores.values.toList()
        ..sort((a, b) => b.opportunity.compareTo(a.opportunity));
      final active = sorted.take(_maxActiveSymbols).map((v) => v.symbol).toList();
      // Always ensure BTC is included for market analysis
      if (!active.contains('BTCUSDT') && _allSymbols.contains('BTCUSDT')) {
        active.add('BTCUSDT');
      }
      return active;
    }
    return _allSymbols.take(_maxActiveSymbols).toList();
  }"""
if "final Map<String, VolatilityScore> _volScores = {};" in src and "_allSymbols" not in src:
    src = src.replace(state_target, new_state, 1)
    checks.append(('state + getter', '_activeSymbols' in src))
else:
    checks.append(('state + getter', '_activeSymbols' in src))

# 4) Replace SYMBOLS usages with _activeSymbols (except in FALLBACK_SYMBOLS definition)
# Careful: don't touch FALLBACK_SYMBOLS
src = src.replace('FALLBACK_SYMBOLS', '__KEEP_FALLBACK__')
src = src.replace('SYMBOLS', '_activeSymbols')
src = src.replace('__KEEP_FALLBACK__', 'FALLBACK_SYMBOLS')
checks.append(('replace SYMBOLS', '_activeSymbols' in src and 'SYMBOLS = [' not in src))

# 5) Add symbol loader in initState
old_init = """    _loadState();
    Timer(const Duration(seconds: 6), () {"""
new_init = """    _loadState();
    _loadAllSymbols();
    Timer(const Duration(seconds: 6), () {"""
if '_loadAllSymbols' not in src and old_init in src:
    src = src.replace(old_init, new_init)
    checks.append(('init loader', '_loadAllSymbols()' in src))
else:
    checks.append(('init loader', '_loadAllSymbols()' in src))

# 6) Add _loadAllSymbols method
helper = """  Future<void> _loadAllSymbols() async {
    if (_loadingSymbols) return;
    setState(() => _loadingSymbols = true);
    try {
      final symbols = await MarketService.fetchAllSymbols(minVolumeUsdt: 50000000);
      if (symbols != null && symbols.isNotEmpty && mounted) {
        setState(() {
          _allSymbols = symbols;
          // Initialize history maps for new symbols
          for (final s in symbols) {
            _priceHistory.putIfAbsent(s, () => []);
            _highHistory.putIfAbsent(s, () => []);
            _lowHistory.putIfAbsent(s, () => []);
            _volumeHistory.putIfAbsent(s, () => []);
          }
        });
        // Load saved history for new symbols if available
        debugPrint('🎯 Loaded ${symbols.length} symbols from Binance');
      }
    } catch (e) {
      debugPrint('Failed to load symbols: $e');
    } finally {
      if (mounted) setState(() => _loadingSymbols = false);
    }
  }

"""
if '_loadAllSymbols' in src and 'Future<void> _loadAllSymbols' not in src:
    src = src.replace(
        "  Future<void> _loadState() async {",
        helper + "  Future<void> _loadState() async {",
        1,
    )
    checks.append(('loader method', 'Future<void> _loadAllSymbols' in src))
else:
    checks.append(('loader method', 'Future<void> _loadAllSymbols' in src))

# 7) Save/load symbol list
old_save = "'topCoinCount': _topCoinCount,"
new_save = "'topCoinCount': _topCoinCount,\n        'allSymbols': _allSymbols,\n        'maxActive': _maxActiveSymbols,"
if old_save in src and "'allSymbols': _allSymbols" not in src:
    src = src.replace(old_save, new_save)
    checks.append(('save symbols', "'allSymbols': _allSymbols" in src))
else:
    checks.append(('save symbols', "'allSymbols': _allSymbols" in src))

old_load = "_topCoinCount = (s['topCoinCount'] as num?)?.toInt() ?? 10;"
new_load = """_topCoinCount = (s['topCoinCount'] as num?)?.toInt() ?? 10;
        _maxActiveSymbols = (s['maxActive'] as num?)?.toInt() ?? 30;
        if (s['allSymbols'] != null) {
          _allSymbols = (s['allSymbols'] as List).map((e) => e.toString()).toList();
          for (final sym in _allSymbols) {
            _priceHistory.putIfAbsent(sym, () => []);
            _highHistory.putIfAbsent(sym, () => []);
            _lowHistory.putIfAbsent(sym, () => []);
            _volumeHistory.putIfAbsent(sym, () => []);
          }
        }"""
if old_load in src and "s['allSymbols']" not in src:
    src = src.replace(old_load, new_load)
    checks.append(('load symbols', "s['allSymbols']" in src))
else:
    checks.append(('load symbols', "s['allSymbols']" in src))

# 8) Add settings row for maxActiveSymbols
old_settings = "        _settingRow('عدد العملات المُختارة', '$_topCoinCount من ${FALLBACK_SYMBOLS.length}',"
new_settings = "        _settingRow('عدد العملات النشطة', '$_maxActiveSymbols',\n            (v) => setState(() => _maxActiveSymbols = int.tryParse(v) ?? _maxActiveSymbols)),\n        _settingRow('عدد العملات المُختارة', '$_topCoinCount',"
if old_settings in src and 'عدد العملات النشطة' not in src:
    src = src.replace(old_settings, new_settings)
    checks.append(('settings max active', 'عدد العملات النشطة' in src))
else:
    checks.append(('settings max active', 'عدد العملات النشطة' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Dynamic Symbols Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('==============================')
