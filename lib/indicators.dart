import 'dart:math';

/// V9 Indicators - Only the essentials
/// EMA, RSI, ATR, Volume - simple and reliable
class Ind {
  // ============ EMA ============
  static double? ema(List<double> prices, int period) {
    if (prices.length < period) return null;
    final k = 2 / (period + 1);
    double e = prices.take(period).reduce((a, b) => a + b) / period;
    for (int i = period; i < prices.length; i++) {
      e = prices[i] * k + e * (1 - k);
    }
    return e;
  }

  // ============ SMA ============
  static double? sma(List<double> prices, int period) {
    if (prices.length < period) return null;
    double s = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      s += prices[i];
    }
    return s / period;
  }

  // ============ RSI ============
  static double? rsi(List<double> prices, [int period = 14]) {
    if (prices.length < period + 1) return null;
    double gains = 0, losses = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses -= change;
      }
    }
    final avgGain = gains / period;
    final avgLoss = losses / period;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  // ============ ATR ============
  static double atr(
    List<double> highs,
    List<double> lows,
    List<double> closes, [
    int period = 14,
  ]) {
    if (closes.length < period + 1) return 0;
    double sum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final tr = [
        highs[i] - lows[i],
        (highs[i] - closes[i - 1]).abs(),
        (lows[i] - closes[i - 1]).abs(),
      ].reduce((a, b) => a > b ? a : b);
      sum += tr;
    }
    return sum / period;
  }

  // ============ Volume Surge ============
  static double volumeSurge(List<double> volumes, [int period = 20]) {
    if (volumes.length < period + 1) return 1.0;
    double avg = 0;
    for (int i = volumes.length - period - 1; i < volumes.length - 1; i++) {
      avg += volumes[i];
    }
    avg /= period;
    if (avg == 0) return 1.0;
    return volumes.last / avg;
  }

  // ============ Swing High/Low ============
  static (double, double) swingHL(
    List<double> highs,
    List<double> lows, [
    int lookback = 20,
  ]) {
    if (highs.length < lookback) {
      return (
        lows.isEmpty ? 0.0 : lows.reduce(min),
        highs.isEmpty ? 0.0 : highs.reduce(max),
      );
    }
    final start = highs.length - lookback;
    final hh = highs.sublist(start).reduce(max);
    final ll = lows.sublist(start).reduce(min);
    return (ll, hh);
  }
}
