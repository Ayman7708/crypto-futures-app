import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# ============ 1. Add wakelock import ============
if "package:wakelock_plus" not in src:
    src = src.replace(
        "import 'services.dart';",
        "import 'services.dart';\nimport 'package:wakelock_plus/wakelock_plus.dart';"
    )
checks.append(('wakelock import', 'wakelock_plus' in src))

# ============ 2. Replace SYMBOLS list with 20 coins ============
old_symbols_pattern = re.compile(r"const List<String> SYMBOLS = \[.*?\];", re.DOTALL)
new_symbols = """const List<String> SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT',
  'ADAUSDT', 'DOTUSDT', 'LINKUSDT', 'MATICUSDT', 'AVAXUSDT', 'ATOMUSDT',
  'NEARUSDT', 'FILUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT', 'INJUSDT',
  'SUIUSDT', 'LTCUSDT',
];"""
src = old_symbols_pattern.sub(new_symbols, src, count=1)
checks.append(('20 coins', 'ADAUSDT' in src and 'SUIUSDT' in src))

# ============ 3. Change default SL/TP/Leverage ============
src = src.replace("double _slPercent = 1.0;", "double _slPercent = 2.5;")
src = src.replace("double _tpPercent = 1.5;", "double _tpPercent = 1.2;")
src = src.replace("int _leverage = 10;", "int _leverage = 5;")
src = src.replace("int _scalpThreshold = 60;", "int _scalpThreshold = 45;")
checks.append(('SL/TP/Leverage', '_slPercent = 2.5' in src and '_leverage = 5' in src))

# ============ 4. Add trailing stop fields to Position (in engine.dart later) ============
# We'll handle this in engine.dart

# ============ 5. Auto-start bot in initState ============
old_init_end = """    _loadState();
    Timer(const Duration(seconds: 6), () {
      if (!_loaded && mounted) setState(() => _loaded = true);
    });
  }"""
new_init_end = """    _loadState().then((_) {
      if (mounted && !_running) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_running) _toggleBot();
        });
      }
    });
    WakelockPlus.enable();
    Timer(const Duration(seconds: 6), () {
      if (!_loaded && mounted) setState(() => _loaded = true);
    });
  }"""
if old_init_end in src:
    src = src.replace(old_init_end, new_init_end)
    checks.append(('auto-start', '_toggleBot()' in src and 'WakelockPlus.enable()' in src))
else:
    checks.append(('auto-start', False))

# ============ 6. Disable wakelock on dispose ============
src = src.replace(
    "  void dispose() {\n    _timer?.cancel();",
    "  void dispose() {\n    WakelockPlus.disable();\n    _timer?.cancel();"
)
checks.append(('wakelock dispose', 'WakelockPlus.disable()' in src))

# ============ 7. Change LONG bias default = true (already true) ============
# OK

# ============ 8. Improve _process: break-even + trailing stop ============
old_pos_check = """    if (pos != null) {
      if (price <= pos.stopLoss) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (price >= pos.takeProfit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      final liqPrice = pos.entry * (1 - 1 / pos.leverage);
      if (price <= liqPrice) { _closePosition(symbol, price, 'LIQUIDATED'); return; }
    }"""
new_pos_check = """    if (pos != null) {
      // break-even: if profit reaches half of TP%, move SL to entry
      final profitPct = (price - pos.entry) / pos.entry * 100;
      if (profitPct >= _tpPercent * 0.5) {
        final newSL = pos.entry;
        if (newSL > pos.stopLoss) {
          _positions[symbol] = Position(
            symbol: symbol, entry: pos.entry, size: pos.size, margin: pos.margin,
            stopLoss: newSL, takeProfit: pos.takeProfit, leverage: pos.leverage,
            isScalp: pos.isScalp,
          );
        }
      }
      // trailing stop: after +1%, trail by 0.5%
      if (profitPct >= 1.0) {
        final trailSL = price * (1 - 0.5 / 100);
        final cur = _positions[symbol]!;
        if (trailSL > cur.stopLoss) {
          _positions[symbol] = Position(
            symbol: symbol, entry: cur.entry, size: cur.size, margin: cur.margin,
            stopLoss: trailSL, takeProfit: cur.takeProfit, leverage: cur.leverage,
            isScalp: cur.isScalp,
          );
        }
      }
      if (price <= pos.stopLoss) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (price >= pos.takeProfit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      final liqPrice = pos.entry * (1 - 1 / pos.leverage);
      if (price <= liqPrice) { _closePosition(symbol, price, 'LIQUIDATED'); return; }
    }"""
if old_pos_check in src:
    src = src.replace(old_pos_check, new_pos_check)
    checks.append(('trailing SL', 'trailSL' in src))
else:
    checks.append(('trailing SL', False))

# ============ 9. Loosen entry conditions ============
src = src.replace(
    "if (_longBias) {\n      if (signal.direction == 'LONG' && signal.score >= 55) {",
    "if (_longBias) {\n      if (signal.direction == 'LONG' && signal.score >= 45) {"
)
checks.append(('loosen entry', "signal.score >= 45" in src))

# ============ 10. Scalping priority: more scalp trades ============
src = src.replace(
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= thr) {\n        _openPosition(symbol, price, isScalp: true);\n        return;\n      }",
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 40) {\n        _openPosition(symbol, price, isScalp: true);\n        return;\n      }"
)
checks.append(('more scalps', "signal.score >= 40" in src))

# ============ 11. Save immediately after each trade ============
src = src.replace(
    "    if (_trades.length > 200) _trades.removeLast();\n  }\n\n  void _closePosition",
    "    if (_trades.length > 200) _trades.removeLast();\n    _saveState();\n  }\n\n  void _closePosition"
)
src = src.replace(
    "    if (_trades.length > 200) _trades.removeLast();\n  }\n\n  @override\n  Widget build",
    "    if (_trades.length > 200) _trades.removeLast();\n    _saveState();\n  }\n\n  @override\n  Widget build"
)
checks.append(('save per trade', src.count('_saveState();\n  }\n\n  void _closePosition') > 0))

# ============ 12. Increase loop frequency for scalping ============
src = src.replace("const int LOOP_SECONDS = 10;", "const int LOOP_SECONDS = 5;")
checks.append(('fast loop', 'LOOP_SECONDS = 5' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Patch Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
