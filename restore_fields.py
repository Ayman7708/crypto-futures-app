with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Add missing state fields after _master
target = "  final MasterEngine _master = MasterEngine();"
new_fields = """  final MasterEngine _master = MasterEngine();
  MarketAnalysis? _marketAnalysis;
  final int _maxPositions = 5;
  final Map<String, DateTime> _lastTradeTime = {};
  static const int _cooldownSeconds = 60;"""

if "MarketAnalysis? _marketAnalysis;" not in src and target in src:
    src = src.replace(target, new_fields, 1)
    checks.append(('state fields', 'MarketAnalysis? _marketAnalysis;' in src))
elif 'MarketAnalysis? _marketAnalysis;' in src:
    checks.append(('state fields', True))
else:
    checks.append(('state fields', False))

# 2) Add _canTradeSymbol method
helper = """  bool _canTradeSymbol(String symbol) {
    final last = _lastTradeTime[symbol];
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >= _cooldownSeconds;
  }

"""
if 'bool _canTradeSymbol(' not in src:
    src = src.replace(
        "  void _openPosition(String symbol, double price, {required bool isScalp, bool isLong = true}) {",
        helper + "  void _openPosition(String symbol, double price, {required bool isScalp, bool isLong = true}) {",
        1,
    )
    checks.append(('canTradeSymbol', 'bool _canTradeSymbol(' in src))
else:
    checks.append(('canTradeSymbol', True))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# 3) Fix market_regime.dart num->double
with open('lib/market_regime.dart', 'r', encoding='utf-8') as f:
    mr = f.read()

mr = mr.replace(
    "final altseason = (altTrend - btcTrend).clamp(-100.0, 100.0);",
    "final altseason = ((altTrend - btcTrend).clamp(-100.0, 100.0)).toDouble();"
)
mr = mr.replace(
    "final dominanceProxy = (btcTrend - altTrend).clamp(-100.0, 100.0);",
    "final dominanceProxy = ((btcTrend - altTrend).clamp(-100.0, 100.0)).toDouble();"
)
with open('lib/market_regime.dart', 'w', encoding='utf-8') as f:
    f.write(mr)
checks.append(('clamp toDouble', '.clamp(-100.0, 100.0)).toDouble()' in mr))

print('=== Restore Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=======================')
