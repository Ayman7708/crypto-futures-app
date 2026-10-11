with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) R:R flip: SL tighter, TP wider
src = src.replace("double _slPercent = 2.5;", "double _slPercent = 1.5;")
src = src.replace("double _tpPercent = 1.2;", "double _tpPercent = 3.0;")
checks.append(('SL=1.5, TP=3.0', '_slPercent = 1.5' in src and '_tpPercent = 3.0' in src))

# 2) Higher entry threshold
src = src.replace("int _scalpThreshold = 45;", "int _scalpThreshold = 65;")
checks.append(('threshold 65', '_scalpThreshold = 65' in src))

# 3) LONG bias entry: require higher score
src = src.replace(
    "if (signal.direction == 'LONG' && signal.score >= 45 && learnedOK) {",
    "if (signal.direction == 'LONG' && signal.score >= 60 && learnedOK && _positions.length < _maxPositions) {"
)
checks.append(('LONG ≥60 + max pos', 'signal.score >= 60 && learnedOK' in src))

# 4) Scalp entry: higher score
src = src.replace(
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 40) {",
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 55 && _positions.length < _maxPositions && _canTradeSymbol(symbol)) {"
)
checks.append(('scalp ≥55', 'signal.score >= 55 && _positions.length' in src))

# 5) Add state vars for max positions and cooldown
old_state = "  final LearningEngineV2 _learner = LearningEngineV2();"
new_state = """  final LearningEngineV2 _learner = LearningEngineV2();
  final int _maxPositions = 5;
  final Map<String, DateTime> _lastTradeTime = {};
  static const int _cooldownSeconds = 120;"""
if old_state in src and '_maxPositions' not in src:
    src = src.replace(old_state, new_state)
    checks.append(('max pos state', '_maxPositions' in src))
else:
    checks.append(('max pos state', '_maxPositions' in src))

# 6) Helper method: cooldown check
helper = """  bool _canTradeSymbol(String symbol) {
    final last = _lastTradeTime[symbol];
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >= _cooldownSeconds;
  }

"""
if '_canTradeSymbol' not in src:
    src = src.replace(
        "  void _openPosition(String symbol, double price, {required bool isScalp}) {",
        helper + "  void _openPosition(String symbol, double price, {required bool isScalp}) {"
    )
    checks.append(('cooldown helper', '_canTradeSymbol' in src))
else:
    checks.append(('cooldown helper', True))

# 7) Record trade time when opening
old_open = """    _positions[symbol] = Position(
      symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
      stopLoss: sl, takeProfit: tp, leverage: _leverage, isScalp: isScalp,
    );
    _balance -= _marginPerTrade;"""
new_open = """    _positions[symbol] = Position(
      symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
      stopLoss: sl, takeProfit: tp, leverage: _leverage, isScalp: isScalp,
    );
    _lastTradeTime[symbol] = DateTime.now();
    _balance -= _marginPerTrade;"""
if old_open in src and '_lastTradeTime[symbol] = DateTime.now()' not in src:
    src = src.replace(old_open, new_open)
    checks.append(('record cooldown', '_lastTradeTime[symbol] = DateTime.now()' in src))
else:
    checks.append(('record cooldown', '_lastTradeTime[symbol] = DateTime.now()' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Fix Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('====================')
