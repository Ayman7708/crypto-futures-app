with open('lib/backtest.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Fix _computeTrend - use correct 4h candle at given 1h time index
old_trend = """  /// Compute 4h trend using data up to given time
  static String _computeTrend(List<double> closes4h, DateTime upTo) {
    // Find how many 4h candles exist before `upTo`
    // Simpler: use last N candles as approximation
    // (In production you'd map exactly, but for backtest this is close enough)
    final ema200 = Ind.ema(closes4h, 200);
    if (ema200 == null || closes4h.isEmpty) return 'NONE';

    // Use a sliding window: roughly how many 4h candles back?
    // For simplicity, use last price of closes4h
    final price = closes4h.last;

    if (price > ema200 * 1.005) return 'BULL';
    if (price < ema200 * 0.995) return 'BEAR';
    return 'NEUTRAL';
  }"""

new_trend = """  /// Compute 4h trend using data up to given index
  /// idx1h: current index in 1h candles (0-based)
  /// Since 1h * 4 = 4h, index4h = idx1h ~/ 4
  static String _computeTrendAtIndex(List<double> closes4h, int idx1h) {
    final idx4h = idx1h ~/ 4;
    if (idx4h < 200) return 'NEUTRAL';

    // Get closes up to idx4h
    final subset = closes4h.sublist(0, idx4h + 1);
    final ema200 = Ind.ema(subset, 200);
    if (ema200 == null || subset.isEmpty) return 'NEUTRAL';

    final price = subset.last;
    if (price > ema200 * 1.005) return 'BULL';
    if (price < ema200 * 0.995) return 'BEAR';
    return 'NEUTRAL';
  }"""

if old_trend in src:
    src = src.replace(old_trend, new_trend)
    print("✅ Fixed _computeTrend function")

# Fix call site
old_call = "final trend = _computeTrend(closes4h, now);"
new_call = "final trend = _computeTrendAtIndex(closes4h, i);"
if old_call in src:
    src = src.replace(old_call, new_call)
    print("✅ Fixed call site")

with open('lib/backtest.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/backtest.dart', 'r', encoding='utf-8') as f:
    final = f.read()

print()
print(f"✅ _computeTrendAtIndex used: {'_computeTrendAtIndex(closes4h, i)' in final}")
print(f"📊 Braces: {final.count('{')} / {final.count('}')}")
