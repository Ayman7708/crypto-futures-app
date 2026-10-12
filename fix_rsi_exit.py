with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Replace the aggressive RSI exit with a condition that requires BEARISH confirmation too
old_exit = """    if (pos != null) {
      if (rsi > 75 || (ss < sl && rsi > 70)) {
        _closePosition(symbol, price, 'SELL');
      }
      return;
    }"""

new_exit = """    if (pos != null) {
      // Only exit on extreme conditions: RSI > 85 AND bearish SMA cross
      // This lets winning positions run with trailing stop
      final rsiVeryHigh = rsi > 85;
      final smaBearish = ss < sl;
      if (rsiVeryHigh && smaBearish) {
        _closePosition(symbol, price, 'SELL');
      }
      // If profit is already strong (>= 5%), let trailing handle it
      return;
    }"""

if old_exit in src:
    src = src.replace(old_exit, new_exit)
    checks.append(('RSI exit loosened', 'rsiVeryHigh' in src))
else:
    checks.append(('RSI exit loosened', False))

# 2) Increase cooldown from 60 to 600 seconds (10 min)
src = src.replace(
    "static const int _cooldownSeconds = 60;",
    "static const int _cooldownSeconds = 600;"
)
checks.append(('cooldown 10min', '_cooldownSeconds = 600' in src))

# 3) Prevent re-entry after profit on same coin (profit lockout)
old_open = """  void _openPosition(String symbol, double price, {required bool isScalp, bool isLong = true}) {
    final size = (_marginPerTrade * _leverage) / price;"""

new_open = """  final Map<String, DateTime> _lastProfitTime = {};

  void _openPosition(String symbol, double price, {required bool isScalp, bool isLong = true}) {
    // Profit lockout: don't reopen same coin for 15 min after a profitable close
    final lastProfit = _lastProfitTime[symbol];
    if (lastProfit != null) {
      final mins = DateTime.now().difference(lastProfit).inMinutes;
      if (mins < 15) return;
    }
    final size = (_marginPerTrade * _leverage) / price;"""

if old_open in src and '_lastProfitTime' not in src:
    src = src.replace(old_open, new_open)
    checks.append(('profit lockout', '_lastProfitTime' in src))
else:
    checks.append(('profit lockout', '_lastProfitTime' in src))

# 4) Record profit time when closing
old_close = """    _positions.remove(symbol);
    String emoji = '🔴';"""

new_close = """    _positions.remove(symbol);
    if (pnl > 0) {
      _lastProfitTime[symbol] = DateTime.now();
    }
    String emoji = '🔴';"""

if old_close in src and '_lastProfitTime[symbol] = DateTime.now()' not in src:
    src = src.replace(old_close, new_close)
    checks.append(('record profit time', '_lastProfitTime[symbol] = DateTime.now()' in src))
else:
    checks.append(('record profit time', '_lastProfitTime[symbol] = DateTime.now()' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Fix RSI Exit ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('====================')
