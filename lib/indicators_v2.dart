import 'dart:math';

class IndicatorsV2 {
  // ============= KDJ =============
  static (double?, double?, double?) kdj(
    List<double> highs, List<double> lows, List<double> closes,
    [int period = 9]) {
    if (closes.length < period) return (null, null, null);
    final start = closes.length - period;
    final hh = highs.sublist(start).reduce(max);
    final ll = lows.sublist(start).reduce(min);
    if (hh == ll) return (50.0, 50.0, 50.0);
    final rsv = (closes.last - ll) / (hh - ll) * 100;
    // Approximate K and D (without full history)
    final k = rsv * 0.667 + 50 * 0.333;
    final d = k * 0.667 + 50 * 0.333;
    final j = 3 * k - 2 * d;
    return (k, d, j);
  }

  // ============= RVI (Relative Volatility Index) =============
  static double? rvi(List<double> closes, [int period = 10]) {
    if (closes.length < period + 1) return null;
    double upSum = 0, dnSum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final ch = closes[i] - closes[i - 1];
      if (ch > 0) upSum += ch; else dnSum += ch.abs();
    }
    final total = upSum + dnSum;
    return total == 0 ? 50 : 100 * upSum / total;
  }

  // ============= TSI (True Strength Index) =============
  static double? tsi(List<double> closes, [int long = 25, int short = 13]) {
    if (closes.length < long + 5) return null;
    final mom = <double>[];
    for (int i = 1; i < closes.length; i++) {
      mom.add(closes[i] - closes[i - 1]);
    }
    final e1 = emaSeriesCalc(mom, long);
    final e2 = emaSeriesCalc(e1, short);
    if (e2.isEmpty) return null;
    final absMom = mom.map((e) => e.abs()).toList();
    final a1 = emaSeriesCalc(absMom, long);
    final a2 = emaSeriesCalc(a1, short);
    if (a2.isEmpty || a2.last == 0) return null;
    return 100 * e2.last / a2.last;
  }

  // ============= DPO (Detrended Price Oscillator) =============
  static double? dpo(List<double> closes, [int period = 20]) {
    if (closes.length < period + period ~/ 2 + 1) return null;
    final shift = period ~/ 2 + 1;
    final idx = closes.length - 1 - shift;
    double sum = 0;
    for (int i = idx - period + 1; i <= idx; i++) {
      if (i < 0) return null;
      sum += closes[i];
    }
    final sma = sum / period;
    return closes.last - sma;
  }

  // ============= EOM (Ease of Movement) =============
  static double? eom(
    List<double> highs, List<double> lows, List<double> volumes,
    [int period = 14]) {
    if (highs.length < period + 1) return null;
    double total = 0;
    for (int i = highs.length - period; i < highs.length; i++) {
      final dm = (highs[i] + lows[i]) / 2 - (highs[i - 1] + lows[i - 1]) / 2;
      final br = volumes[i] / (highs[i] - lows[i] + 0.0001);
      total += dm / br;
    }
    return total / period;
  }

  // ============= KST (Know Sure Thing) =============
  static double? kst(List<double> closes) {
    if (closes.length < 50) return null;
    final r1 = _roc(closes, 10);
    final r2 = _roc(closes, 15);
    final r3 = _roc(closes, 20);
    final r4 = _roc(closes, 30);
    if (r1 == null || r2 == null || r3 == null || r4 == null) return null;
    return (r1 * 1) + (r2 * 2) + (r3 * 3) + (r4 * 4);
  }

  // ============= Mass Index =============
  static double? massIndex(
    List<double> highs, List<double> lows, [int period = 25]) {
    if (highs.length < period * 2) return null;
    final ema_h = emaSeriesCalc(highs, 9);
    final ema_l = emaSeriesCalc(lows, 9);
    if (ema_h.length != ema_l.length) return null;
    final diff = List<double>.generate(ema_h.length, (i) => (ema_h[i] - ema_l[i]).abs());
    if (diff.length < period * 2) return null;
    final ema1 = emaSeriesCalc(diff, 9);
    if (ema1.length < period) return null;
    final ema2 = emaSeriesCalc(ema1, 9);
    if (ema2.length < period) return null;
    double sum = 0;
    for (int i = ema2.length - period; i < ema2.length; i++) {
      if (ema1[i] == 0) continue;
      sum += ema2[i] / ema1[i];
    }
    return sum;
  }

  // ============= Coppock Curve =============
  static double? coppock(List<double> closes) {
    if (closes.length < 30) return null;
    final r1 = _roc(closes, 14);
    final r2 = _roc(closes, 11);
    if (r1 == null || r2 == null) return null;
    return r1 + r2; // simplified
  }

  // ============= Fisher Transform =============
  static double? fisher(List<double> highs, List<double> lows, List<double> closes, [int period = 10]) {
    if (closes.length < period) return null;
    final start = closes.length - period;
    final hh = highs.sublist(start).reduce(max);
    final ll = lows.sublist(start).reduce(min);
    if (hh == ll) return 0;
    final x = 2 * ((closes.last - ll) / (hh - ll)) - 1;
    final clamped = x.clamp(-0.999, 0.999);
    return 0.5 * log((1 + clamped) / (1 - clamped));
  }

  // ============= Elder Ray (Bull/Bear Power) =============
  static (double?, double?) elderRay(List<double> highs, List<double> lows, List<double> closes, [int period = 13]) {
    final e = _ema(closes, period);
    if (e == null) return (null, null);
    final bull = highs.last - e;
    final bear = lows.last - e;
    return (bull, bear);
  }

  // ============= Schaff Trend Cycle =============
  static double? schaffTrend(List<double> closes, [int fast = 23, int slow = 50, int cycle = 10]) {
    if (closes.length < slow) return null;
    final e1 = _ema(closes, fast);
    final e2 = _ema(closes, slow);
    if (e1 == null || e2 == null) return null;
    final macd = e1 - e2;
    return macd.clamp(-100, 100);
  }

  // ============= Connors RSI =============
  static double? connorsRsi(List<double> closes, [int rsiPeriod = 3, int streakPeriod = 2, int rankPeriod = 100]) {
    if (closes.length < 10) return null;
    // RSI(3)
    final rsi = _rsi(closes, rsiPeriod);
    if (rsi == null) return null;
    // Streak RSI
    int streak = 0;
    for (int i = closes.length - 1; i > 0; i--) {
      if (closes[i] > closes[i - 1]) {
        if (streak >= 0) streak++; else break;
      } else if (closes[i] < closes[i - 1]) {
        if (streak <= 0) streak--; else break;
      } else break;
    }
    final streakScore = (50 + 50 * streak / 10).clamp(0, 100);
    return (rsi + streakScore) / 2;
  }

  // ============= Chande Momentum Oscillator =============
  static double? cmo(List<double> closes, [int period = 14]) {
    if (closes.length < period + 1) return null;
    double up = 0, dn = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final ch = closes[i] - closes[i - 1];
      if (ch > 0) up += ch; else dn += ch.abs();
    }
    final total = up + dn;
    return total == 0 ? 0 : 100 * (up - dn) / total;
  }

  // ============= Ulcer Index =============
  static double? ulcer(List<double> closes, [int period = 14]) {
    if (closes.length < period) return null;
    final start = closes.length - period;
    final hh = closes.sublist(start).reduce(max);
    double sumSq = 0;
    for (int i = start; i < closes.length; i++) {
      if (hh == 0) continue;
      final dd = ((closes[i] - hh) / hh * 100);
      sumSq += dd * dd;
    }
    return sqrt(sumSq / period);
  }

  // ============= Helpers =============
  static List<double> emaSeriesCalc(List<double> arr, int period) {
    if (arr.length < period) return [];
    final k = 2 / (period + 1);
    final out = <double>[];
    double e = arr.take(period).reduce((a, b) => a + b) / period;
    out.add(e);
    for (int i = period; i < arr.length; i++) {
      e = arr[i] * k + e * (1 - k);
      out.add(e);
    }
    return out;
  }

  static double? emaCalc(List<double> arr, int period) {
    if (arr.length < period) return null;
    final k = 2 / (period + 1);
    double e = arr.take(period).reduce((a, b) => a + b) / period;
    for (int i = period; i < arr.length; i++) {
      e = arr[i] * k + e * (1 - k);
    }
    return e;
  }

  static double? _roc(List<double> arr, int period) {
    if (arr.length < period + 1) return null;
    final past = arr[arr.length - period - 1];
    if (past == 0) return 0;
    return (arr.last - past) / past * 100;
  }

  static double? _rsi(List<double> arr, int period) {
    if (arr.length < period + 1) return null;
    double g = 0, l = 0;
    for (int i = arr.length - period; i < arr.length; i++) {
      final d = arr[i] - arr[i - 1];
      if (d > 0) g += d; else l -= d;
    }
    if (l == 0) return 100;
    final rs = g / l;
    return 100 - (100 / (1 + rs));
  }
}
