with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) import
if "import 'strategies.dart';" not in src:
    src = src.replace("import 'learning.dart';", "import 'learning.dart';\nimport 'strategies.dart';")
checks.append(('import', "import 'strategies.dart';" in src))

# 2) state field
if "_master" not in src:
    src = src.replace(
        "  final LearningEngineV2 _learner = LearningEngineV2();",
        "  final LearningEngineV2 _learner = LearningEngineV2();\n  final MasterEngine _master = MasterEngine();"
    )
checks.append(('state field', "_master" in src))

# 3) Replace _process logic to use master engine
old_block = """    final scalp = ScalpAnalyzer.analyze(
      closes: hist, highs: _highHistory[symbol]!, lows: _lowHistory[symbol]!,
      smaShort: _smaShort, smaLong: _smaLong, rsiBuy: _rsiBuy,
    );
    _scalpSignals[symbol] = scalp;"""

new_block = """    // Master engine: evaluate all strategies in parallel
    final strategyResults = _master.evaluateAll(
      closes: hist, highs: _highHistory[symbol]!,
      lows: _lowHistory[symbol]!, volumes: _volumeHistory[symbol]!,
    );
    final (combinedScore, topStrategies, _) = _master.combinedScore(strategyResults);
    final oldScalp = ScalpAnalyzer.analyze(
      closes: hist, highs: _highHistory[symbol]!, lows: _lowHistory[symbol]!,
      smaShort: _smaShort, smaLong: _smaLong, rsiBuy: _rsiBuy,
    );
    final scalp = ScalpSignal(
      (oldScalp.score * 0.3 + combinedScore * 0.7).toInt(),
      combinedScore >= _scalpThreshold ? 'LONG' : 'NONE',
      topStrategies,
    );
    _scalpSignals[symbol] = scalp;
    _masterTopStrategies[symbol] = topStrategies;"""
if old_block in src:
    src = src.replace(old_block, new_block)
    checks.append(('process master', '_master.evaluateAll' in src))
else:
    checks.append(('process master', False))

# 4) Add map for top strategies
if "_masterTopStrategies" not in src:
    src = src.replace(
        "  final Map<String, ScalpSignal> _scalpSignals = {};",
        "  final Map<String, ScalpSignal> _scalpSignals = {};\n  final Map<String, String> _masterTopStrategies = {};"
    )
    checks.append(('map top strategies', "_masterTopStrategies" in src))
else:
    checks.append(('map top strategies', True))

# 5) Update master on trade close
old_close = """    _learner.updateFromTrade(
      wasWin: wasWin, pnl: pnl,
      signalReason: reason_str, direction: 'LONG',
      activeIndicators: {'sma','ema','rsi','macd','bollinger','stoch','adx','vwap','supertrend','volume_surge'},
    );"""
new_close = """    _learner.updateFromTrade(
      wasWin: wasWin, pnl: pnl,
      signalReason: reason_str, direction: 'LONG',
      activeIndicators: {'sma','ema','rsi','macd','bollinger','stoch','adx','vwap','supertrend','volume_surge'},
    );
    // Update each master strategy weight
    for (final s in _master.strategies) {
      _master.updateFromTrade(s.name, wasWin);
    }"""
if old_close in src and '_master.updateFromTrade' not in src:
    src = src.replace(old_close, new_close)
    checks.append(('update master', '_master.updateFromTrade' in src))
else:
    checks.append(('update master', '_master.updateFromTrade' in src))

# 6) Save master state
old_save = "        'learner': _learner.toJson(),"
new_save = "        'learner': _learner.toJson(),\n        'master': _master.toJson(),"
if old_save in src:
    src = src.replace(old_save, new_save)
    checks.append(('save master', "'master': _master.toJson()" in src))
else:
    checks.append(('save master', False))

# 7) Load master state
old_load = "          _learner.loadFromJson(Map<String, dynamic>.from(s['learner']));\n        }"
new_load = """          _learner.loadFromJson(Map<String, dynamic>.from(s['learner']));
        }
        if (s['master'] != null) {
          _master.loadFromJson(Map<String, dynamic>.from(s['master']));
        }"""
if old_load in src:
    src = src.replace(old_load, new_load)
    checks.append(('load master', '_master.loadFromJson' in src))
else:
    checks.append(('load master', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Master Patch Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('============================')
