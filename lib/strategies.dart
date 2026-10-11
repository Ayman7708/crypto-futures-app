import 'dart:math';
import 'engine.dart';

// ==================== INDICATORS ====================
class ExtraIndicators {
  static double? aroon(List<double> highs, List<double> lows, [int period = 14]) {
    if (highs.length < period + 1) return null;
    int hiIdx = 0, loIdx = 0;
    for (int i = highs.length - period; i < highs.length; i++) {
      if (highs[i] >= highs[highs.length - period + hiIdx]) hiIdx = i - (highs.length - period);
      if (lows[i] <= lows[lows.length - period + loIdx]) loIdx = i - (lows.length - period);
    }
    final up = 100.0 * hiIdx / period;
    final dn = 100.0 * loIdx / period;
    return up - dn;
  }

  static double? trix(List<double> closes, [int period = 15]) {
    if (closes.length < period * 3) return null;
    List<double> e1 = _emaSeries(closes, period);
    List<double> e2 = _emaSeries(e1, period);
    List<double> e3 = _emaSeries(e2, period);
    if (e3.length < 2 || e3[e3.length - 2] == 0) return null;
    return (e3.last - e3[e3.length - 2]) / e3[e3.length - 2] * 100;
  }

  static double? vortex(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period + 1) return null;
    double vmP = 0, vmM = 0, tr = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      vmP += (highs[i] - lows[i - 1]).abs();
      vmM += (lows[i] - highs[i - 1]).abs();
      tr += max(highs[i] - lows[i], max((highs[i] - closes[i - 1]).abs(), (lows[i] - closes[i - 1]).abs()));
    }
    if (tr == 0) return 0;
    return vmP / tr - vmM / tr;
  }

  static double? cmf(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, [int period = 20]) {
    if (closes.length < period) return null;
    double mfv = 0, vol = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final rng = highs[i] - lows[i];
      if (rng == 0) continue;
      final m = ((closes[i] - lows[i]) - (highs[i] - closes[i])) / rng;
      mfv += m * volumes[i];
      vol += volumes[i];
    }
    if (vol == 0) return 0;
    return mfv / vol;
  }

  static double? forceIndex(List<double> closes, List<double> volumes, [int period = 13]) {
    if (closes.length < period + 1) return null;
    double total = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      total += (closes[i] - closes[i - 1]) * volumes[i];
    }
    return total / period;
  }

  static double? awesome(List<double> closes) {
    if (closes.length < 34) return null;
    double sum5 = 0, sum34 = 0;
    for (int i = closes.length - 5; i < closes.length; i++) sum5 += closes[i];
    for (int i = closes.length - 34; i < closes.length; i++) sum34 += closes[i];
    return (sum5 / 5) - (sum34 / 34);
  }

  static double? ultimate(List<double> highs, List<double> lows, List<double> closes, [int p1 = 7, int p2 = 14, int p3 = 28]) {
    if (closes.length < p3 + 1) return null;
    double bp1 = 0, bp2 = 0, bp3 = 0, tr1 = 0, tr2 = 0, tr3 = 0;
    for (int i = closes.length - p3; i < closes.length; i++) {
      final trueLow = min(lows[i], closes[i - 1]);
      final bp = closes[i] - trueLow;
      final tr = max(highs[i], closes[i - 1]) - trueLow;
      tr3 += tr; bp3 += bp;
      if (i >= closes.length - p2) { tr2 += tr; bp2 += bp; }
      if (i >= closes.length - p1) { tr1 += tr; bp1 += bp; }
    }
    if (tr1 == 0 || tr2 == 0 || tr3 == 0) return null;
    return 100 * (4 * bp1 / tr1 + 2 * bp2 / tr2 + bp3 / tr3) / 7;
  }

  static (double?, double?, double?) donchian(List<double> highs, List<double> lows, [int period = 20]) {
    if (highs.length < period) return (null, null, null);
    final hh = highs.sublist(highs.length - period).reduce(max);
    final ll = lows.sublist(lows.length - period).reduce(min);
    return (ll, (hh + ll) / 2, hh);
  }

  static (double?, double?, double?) pivotPoints(List<double> highs, List<double> lows, List<double> closes) {
    if (closes.length < 2) return (null, null, null);
    final h = highs[highs.length - 2];
    final l = lows[lows.length - 2];
    final c = closes[closes.length - 2];
    final p = (h + l + c) / 3;
    return ((2 * p) - h, p, (2 * p) - l);
  }

  static (double?, String) parabolicSar(List<double> highs, List<double> lows, [double step = 0.02, double maxAcc = 0.2]) {
    if (highs.length < 3) return (null, 'NEUTRAL');
    bool up = highs[1] > highs[0];
    double sar = up ? lows[0] : highs[0];
    double ep = up ? highs[0] : lows[0];
    double af = step;
    for (int i = 2; i < highs.length; i++) {
      sar = sar + af * (ep - sar);
      if (up) {
        if (lows[i] < sar) { up = false; sar = ep; ep = lows[i]; af = step; }
        else if (highs[i] > ep) { ep = highs[i]; af = min(af + step, maxAcc); }
      } else {
        if (highs[i] > sar) { up = true; sar = ep; ep = highs[i]; af = step; }
        else if (lows[i] < ep) { ep = lows[i]; af = min(af + step, maxAcc); }
      }
    }
    return (sar, up ? 'BUY' : 'SELL');
  }

  static List<double> _emaSeries(List<double> arr, int period) {
    if (arr.isEmpty) return [];
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
}

// ==================== STRATEGY BASE ====================
class StrategyResult {
  final String name;
  final String direction; // LONG / SHORT / NONE
  final int score;        // 0-100
  final String reason;
  StrategyResult(this.name, this.direction, this.score, this.reason);
}

abstract class Strategy {
  String get name;
  StrategyResult evaluate({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required List<double> volumes,
  });
}

// ==================== STRATEGY 1: MEAN REVERSION ====================
class MeanReversionStrategy extends Strategy {
  @override
  String get name => 'MeanReversion';

  @override
  StrategyResult evaluate({
    required List<double> closes, required List<double> highs,
    required List<double> lows, required List<double> volumes,
  }) {
    if (closes.length < 30) return StrategyResult(name, 'NONE', 0, 'بيانات قليلة');
    int score = 0;
    final r = <String>[];

    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null && rsi < 25) { score += 30; r.add('RSI<25'); }
    else if (rsi != null && rsi < 35) { score += 20; r.add('RSI<35'); }

    final (low, mid, up) = Indicators.bollinger(closes, 20, 2);
    if (low != null && closes.last <= low) { score += 30; r.add('تحت BB'); }
    else if (low != null && closes.last <= low * 1.01) { score += 15; r.add('قرب BB'); }

    final stoch = Indicators.stochastic(highs, lows, closes, 14);
    if (stoch != null && stoch < 20) { score += 20; r.add('Stoch'); }

    final wr = ExtraIndicators.ultimate(highs, lows, closes);
    if (wr != null && wr < 35) { score += 20; r.add('UO'); }

    return StrategyResult(name, score >= 60 ? 'LONG' : 'NONE', score, r.join('+'));
  }
}

// ==================== STRATEGY 2: MOMENTUM ====================
class MomentumStrategy extends Strategy {
  @override
  String get name => 'Momentum';

  @override
  StrategyResult evaluate({
    required List<double> closes, required List<double> highs,
    required List<double> lows, required List<double> volumes,
  }) {
    if (closes.length < 40) return StrategyResult(name, 'NONE', 0, 'بيانات قليلة');
    int score = 0;
    final r = <String>[];

    final roc = _roc(closes, 10);
    if (roc != null && roc > 2) { score += 25; r.add('ROC'); }

    final ao = ExtraIndicators.awesome(closes);
    if (ao != null && ao > 0) { score += 25; r.add('AO'); }

    final (macd, sig, hist) = Indicators.macd(closes);
    if (hist != null && hist > 0 && macd! > sig!) { score += 25; r.add('MACD'); }

    final trix = ExtraIndicators.trix(closes);
    if (trix != null && trix > 0) { score += 25; r.add('TRIX'); }

    return StrategyResult(name, score >= 60 ? 'LONG' : 'NONE', score, r.join('+'));
  }

  double? _roc(List<double> arr, int p) {
    if (arr.length < p + 1) return null;
    final past = arr[arr.length - p - 1];
    if (past == 0) return 0;
    return (arr.last - past) / past * 100;
  }
}

// ==================== STRATEGY 3: BREAKOUT ====================
class BreakoutStrategy extends Strategy {
  @override
  String get name => 'Breakout';

  @override
  StrategyResult evaluate({
    required List<double> closes, required List<double> highs,
    required List<double> lows, required List<double> volumes,
  }) {
    if (closes.length < 30) return StrategyResult(name, 'NONE', 0, 'بيانات قليلة');
    int score = 0;
    final r = <String>[];

    final (dLow, dMid, dHigh) = ExtraIndicators.donchian(highs, lows, 20);
    if (dHigh != null && closes.last >= dHigh * 0.99) { score += 35; r.add('Donchian'); }

    final vs = _volumeSurge(volumes, 20);
    if (vs > 1.5) { score += 30; r.add('Vol x${vs.toStringAsFixed(1)}'); }

    final (bbLow, bbMid, bbUp) = Indicators.bollinger(closes, 20, 2);
    if (bbLow != null && bbMid != null && bbMid != 0) {
      final width = (bbUp! - bbLow) / bbMid;
      if (width < 0.03) { score += 20; r.add('Squeeze'); }
    }

    final adx = _adx(highs, lows, closes, 14);
    if (adx != null && adx > 20) { score += 15; r.add('ADX'); }

    return StrategyResult(name, score >= 60 ? 'LONG' : 'NONE', score, r.join('+'));
  }

  double _volumeSurge(List<double> v, int p) {
    if (v.length < p + 1) return 1;
    final avg = v.sublist(v.length - p - 1, v.length - 1).reduce((a, b) => a + b) / p;
    return avg == 0 ? 1 : v.last / avg;
  }

  double? _adx(List<double> h, List<double> l, List<double> c, int p) {
    if (c.length < p + 2) return null;
    double atr = 0, pdm = 0, ndm = 0;
    for (int i = c.length - p; i < c.length; i++) {
      atr += max(h[i] - l[i], max((h[i] - c[i-1]).abs(), (l[i] - c[i-1]).abs()));
      final up = h[i] - h[i-1];
      final dn = l[i-1] - l[i];
      if (up > dn && up > 0) pdm += up;
      if (dn > up && dn > 0) ndm += dn;
    }
    if (atr == 0) return 0;
    final pdi = 100 * pdm / atr;
    final ndi = 100 * ndm / atr;
    final s = pdi + ndi;
    return s == 0 ? 0 : (pdi - ndi).abs() / s * 100;
  }
}

// ==================== STRATEGY 4: TREND FOLLOWING ====================
class TrendStrategy extends Strategy {
  @override
  String get name => 'Trend';

  @override
  StrategyResult evaluate({
    required List<double> closes, required List<double> highs,
    required List<double> lows, required List<double> volumes,
  }) {
    if (closes.length < 50) return StrategyResult(name, 'NONE', 0, 'بيانات قليلة');
    int score = 0;
    final r = <String>[];

    final e12 = _ema(closes, 12);
    final e26 = _ema(closes, 26);
    final e50 = _ema(closes, 50);
    if (e12 != null && e26 != null && e12 > e26) { score += 25; r.add('EMA12>26'); }
    if (e26 != null && e50 != null && e26 > e50) { score += 15; r.add('EMA26>50'); }

    final (st, dir) = ExtraIndicators.parabolicSar(highs, lows);
    if (dir == 'BUY') { score += 25; r.add('PSAR'); }

    final vortex = ExtraIndicators.vortex(highs, lows, closes, 14);
    if (vortex != null && vortex > 0.1) { score += 20; r.add('Vortex'); }

    final aroon = ExtraIndicators.aroon(highs, lows, 14);
    if (aroon != null && aroon > 30) { score += 15; r.add('Aroon'); }

    return StrategyResult(name, score >= 60 ? 'LONG' : 'NONE', score, r.join('+'));
  }

  double? _ema(List<double> a, int p) {
    if (a.length < p) return null;
    final k = 2 / (p + 1);
    double e = a.take(p).reduce((x, y) => x + y) / p;
    for (int i = p; i < a.length; i++) e = a[i] * k + e * (1 - k);
    return e;
  }
}

// ==================== STRATEGY 5: SCALPING ====================
class ScalpStrategy extends Strategy {
  @override
  String get name => 'Scalp';

  @override
  StrategyResult evaluate({
    required List<double> closes, required List<double> highs,
    required List<double> lows, required List<double> volumes,
  }) {
    if (closes.length < 20) return StrategyResult(name, 'NONE', 0, 'بيانات قليلة');
    int score = 0;
    final r = <String>[];

    final cmf = ExtraIndicators.cmf(highs, lows, closes, volumes, 20);
    if (cmf != null && cmf > 0.1) { score += 25; r.add('CMF+'); }

    final fi = ExtraIndicators.forceIndex(closes, volumes);
    if (fi != null && fi > 0) { score += 20; r.add('Force+'); }

    final rsi = Indicators.rsi(closes, 7);
    if (rsi != null && rsi < 40 && rsi > 25) { score += 20; r.add('RSI7'); }

    final stoch = Indicators.stochastic(highs, lows, closes, 9);
    if (stoch != null && stoch < 30) { score += 15; r.add('Stoch'); }

    final vs = _vs(volumes, 10);
    if (vs > 1.3) { score += 20; r.add('Vol'); }

    return StrategyResult(name, score >= 55 ? 'LONG' : 'NONE', score, r.join('+'));
  }

  double _vs(List<double> v, int p) {
    if (v.length < p + 1) return 1;
    final avg = v.sublist(v.length - p - 1, v.length - 1).reduce((a, b) => a + b) / p;
    return avg == 0 ? 1 : v.last / avg;
  }
}

// ==================== MASTER ENGINE ====================
class MasterEngine {
  final List<Strategy> strategies = [
    MeanReversionStrategy(),
    MomentumStrategy(),
    BreakoutStrategy(),
    TrendStrategy(),
    ScalpStrategy(),
  ];

  final Map<String, double> weights = {
    'MeanReversion': 1.0,
    'Momentum': 1.0,
    'Breakout': 1.2,
    'Trend': 1.0,
    'Scalp': 1.1,
  };

  final Map<String, int> wins = {};
  final Map<String, int> losses = {};

  MasterEngine() {
    for (final s in strategies) { wins[s.name] = 0; losses[s.name] = 0; }
  }

  List<StrategyResult> evaluateAll({
    required List<double> closes, required List<double> highs,
    required List<double> lows, required List<double> volumes,
  }) {
    return strategies.map((s) => s.evaluate(
      closes: closes, highs: highs, lows: lows, volumes: volumes,
    )).toList();
  }

  // Combined score with weights
  (int, String, List<String>) combinedScore(List<StrategyResult> results) {
    double weighted = 0;
    double totalW = 0;
    final names = <String>[];
    for (final r in results) {
      final w = weights[r.name] ?? 1.0;
      if (r.direction == 'LONG') {
        weighted += r.score * w;
        totalW += w;
        names.add('${r.name}:${r.score}');
      }
    }
    if (totalW == 0) return (0, '', names);
    // Bonus if multiple strategies agree
    final agreeCount = results.where((r) => r.direction == 'LONG').length;
    final avgScore = weighted / totalW;
    final bonus = agreeCount >= 3 ? 15 : (agreeCount >= 2 ? 8 : 0);
    return ((avgScore + bonus).clamp(0, 100).toInt(), names.join('|'), names);
  }

  void updateFromTrade(String strategyName, bool wasWin) {
    if (wasWin) {
      wins[strategyName] = (wins[strategyName] ?? 0) + 1;
      weights[strategyName] = min(2.5, (weights[strategyName] ?? 1.0) * 1.10);
    } else {
      losses[strategyName] = (losses[strategyName] ?? 0) + 1;
      weights[strategyName] = max(0.3, (weights[strategyName] ?? 1.0) * 0.92);
    }
  }

  Map<String, dynamic> toJson() => {
    'weights': weights,
    'wins': wins,
    'losses': losses,
  };

  void loadFromJson(Map<String, dynamic> j) {
    try {
      if (j['weights'] != null) {
        (j['weights'] as Map).forEach((k, v) {
          weights[k.toString()] = (v as num).toDouble();
        });
      }
      if (j['wins'] != null) {
        (j['wins'] as Map).forEach((k, v) {
          wins[k.toString()] = v as int;
        });
      }
      if (j['losses'] != null) {
        (j['losses'] as Map).forEach((k, v) {
          losses[k.toString()] = v as int;
        });
      }
    } catch (_) {}
  }
}
