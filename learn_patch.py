with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) import
if "import 'learning.dart';" not in src:
    src = src.replace("import 'services.dart';", "import 'services.dart';\nimport 'learning.dart';")
checks.append(('import', "import 'learning.dart';" in src))

# 2) state field
if "_learner" not in src:
    src = src.replace(
        "  Timer? _timer;",
        "  Timer? _timer;\n  final LearningEngineV2 _learner = LearningEngineV2();"
    )
checks.append(('state field', "_learner" in src))

# 3) detect regime in _tick (after processing each symbol)
old_tick_end = "        _process(sym, last.close);\n      }\n    });\n    _saveState();"
new_tick_end = """        _process(sym, last.close);
      }
      // Update market regime from BTC (reference)
      if (_priceHistory['BTCUSDT'] != null && _priceHistory['BTCUSDT']!.length >= 30) {
        _learner.detectRegime(
          closes: _priceHistory['BTCUSDT']!,
          highs: _highHistory['BTCUSDT']!,
          lows: _lowHistory['BTCUSDT']!,
        );
      }
    });
    _saveState();"""
if old_tick_end in src:
    src = src.replace(old_tick_end, new_tick_end)
    checks.append(('detect regime', '_learner.detectRegime' in src))
else:
    checks.append(('detect regime', False))

# 4) use learned threshold in _process
src = src.replace(
    "    if (_longBias) {\n      if (signal.direction == 'LONG' && signal.score >= 45) {",
    "    final learnedOK = _learner.shouldEnter(signal.score);\n    if (_longBias) {\n      if (signal.direction == 'LONG' && signal.score >= 45 && learnedOK) {"
)
checks.append(('use learned threshold', '_learner.shouldEnter' in src))

# 5) update from trade in _closePosition
old_close_head = """  void _closePosition(String symbol, double price, String reason) {
    final pos = _positions[symbol];
    if (pos == null) return;
    final pnl = (price - pos.entry) * pos.size;"""
new_close_head = """  void _closePosition(String symbol, double price, String reason) {
    final pos = _positions[symbol];
    if (pos == null) return;
    final pnl = (price - pos.entry) * pos.size;
    final wasWin = pnl > 0;
    final reason_str = _scalpSignals[symbol]?.reason ?? '';
    _learner.updateFromTrade(
      wasWin: wasWin, pnl: pnl,
      signalReason: reason_str, direction: 'LONG',
      activeIndicators: {'sma','ema','rsi','macd','bollinger','stoch','adx','vwap','supertrend','volume_surge'},
    );"""
if old_close_head in src:
    src = src.replace(old_close_head, new_close_head)
    checks.append(('update from trade', '_learner.updateFromTrade' in src))
else:
    checks.append(('update from trade', False))

# 6) Save learner in _saveState
old_save = """        'longBias': _longBias,
        'indicators': _indicators.map((i) => i.toJson()).toList(),
      },
    );"""
new_save = """        'longBias': _longBias,
        'indicators': _indicators.map((i) => i.toJson()).toList(),
        'learner': _learner.toJson(),
      },
    );"""
if old_save in src:
    src = src.replace(old_save, new_save)
    checks.append(('save learner', "'learner': _learner.toJson()" in src))
else:
    checks.append(('save learner', False))

# 7) Load learner in _loadState
old_load = """        if (s['indicators'] != null) {
          final list = (s['indicators'] as List).map((e) => IndicatorDef.fromJson(e as Map<String, dynamic>)).toList();
          if (list.isNotEmpty) _indicators = list;
        }"""
new_load = """        if (s['indicators'] != null) {
          final list = (s['indicators'] as List).map((e) => IndicatorDef.fromJson(e as Map<String, dynamic>)).toList();
          if (list.isNotEmpty) _indicators = list;
        }
        if (s['learner'] != null) {
          _learner.loadFromJson(Map<String, dynamic>.from(s['learner']));
        }"""
if old_load in src:
    src = src.replace(old_load, new_load)
    checks.append(('load learner', '_learner.loadFromJson' in src))
else:
    checks.append(('load learner', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Patch Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
