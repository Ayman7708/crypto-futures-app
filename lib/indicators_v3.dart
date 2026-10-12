import 'dart:math';

class IndicatorsV3 {
  // Zigzag (simplified peaks detection)
  static double? zigzag(List<double> closes, [int period = 5]) {
    if (closes.length < period * 2) return null;
    int pivots = 0;
    for (int i = closes.length - period; i < closes.length - 1; i++) {
      bool isHigh = true, isLow = true;
      for (int j = i - period; j <= i + period; j++) {
        if (j < 0 || j >= closes.length) continue;
        if (closes[j] > closes[i]) isHigh = false;
        if (closes[j] < closes[i]) isLow = false;
      }
      if (isHigh || isLow) pivots++;
    }
    return pivots.toDouble();
  }

  // Heikin-Ashi trend
  static String heikinAshi(List<double> opens, List<double> highs, List<double> lows, List<double> closes) {
    if (closes.length < 2) return 'NEUTRAL';
    double haClose = (opens.last + highs.last + lows.last + closes.last) / 4;
    double haOpen = (opens[opens.length - 2] + closes[closes.length - 2]) / 2;
    return haClose > haOpen ? 'BULL' : 'BEAR';
  }

  // Alligator (Bill Williams)
  static (double?, double?, double?) alligator(List<double> closes) {
    if (closes.length < 21) return (null, null, null);
    final jaw = smaCalc(closes, 13);
    final teeth = smaCalc(closes, 8);
    final lips = smaCalc(closes, 5);
    return (jaw, teeth, lips);
  }

  // Fractals
  static int fractals(List<double> highs, List<double> lows, [int period = 2]) {
    if (highs.length < period * 2 + 1) return 0;
    int count = 0;
    for (int i = period; i < highs.length - period; i++) {
      bool up = true, dn = true;
      for (int j = 1; j <= period; j++) {
        if (highs[i] <= highs[i - j] || highs[i] <= highs[i + j]) up = false;
        if (lows[i] >= lows[i - j] || lows[i] >= lows[i + j]) dn = false;
      }
      if (up || dn) count++;
    }
    return count;
  }

  // Gator Oscillator (simplified)
  static double? gator(List<double> closes) {
    final (j, t, l) = alligator(closes);
    if (j == null || t == null || l == null) return null;
    return ((j - t).abs() - (t - l).abs()).abs();
  }

  // Accelerator Oscillator (AC)
  static double? accelerator(List<double> highs, List<double> lows, List<double> closes) {
    if (closes.length < 34) return null;
    double ao(int idx) {
      double s5 = 0, s34 = 0;
      for (int i = idx - 4; i <= idx; i++) s5 += (highs[i] + lows[i]) / 2;
      for (int i = idx - 33; i <= idx; i++) s34 += (highs[i] + lows[i]) / 2;
      return (s5 / 5) - (s34 / 34);
    }
    final aoNow = ao(closes.length - 1);
    final aoPrev = ao(closes.length - 6);
    return aoNow - aoPrev;
  }

  // Bulls Power
  static double? bullsPower(List<double> highs, List<double> closes, [int period = 13]) {
    final e = emaCalc(closes, period);
    if (e == null) return null;
    return highs.last - e;
  }

  // Bears Power
  static double? bearsPower(List<double> lows, List<double> closes, [int period = 13]) {
    final e = emaCalc(closes, period);
    if (e == null) return null;
    return lows.last - e;
  }

  // Chaikin Oscillator
  static double? chaikinOscillator(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, [int fast = 3, int slow = 10]) {
    if (closes.length < slow + 2) return null;
    final adl = <double>[];
    double sum = 0;
    for (int i = 1; i < closes.length; i++) {
      final rng = highs[i] - lows[i];
      final mfm = rng == 0 ? 0 : ((closes[i] - lows[i]) - (highs[i] - closes[i])) / rng;
      sum += mfm * volumes[i];
      adl.add(sum);
    }
    if (adl.length < slow) return null;
    final e1 = emaCalc(adl, fast);
    final e2 = emaCalc(adl, slow);
    if (e1 == null || e2 == null) return null;
    return e1 - e2;
  }

  // Bollinger %B
  static double? bollingerPercentB(List<double> closes, [int period = 20, double mult = 2]) {
    if (closes.length < period) return null;
    final slice = closes.sublist(closes.length - period);
    final mean = slice.reduce((a, b) => a + b) / period;
    double v = 0;
    for (final x in slice) v += pow(x - mean, 2);
    v /= period;
    final sd = sqrt(v);
    if (sd == 0) return 0.5;
    return (closes.last - (mean - mult * sd)) / (2 * mult * sd);
  }

  // Choppiness Index
  static double? choppiness(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period + 1) return null;
    double tr = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      tr += max(highs[i] - lows[i], max((highs[i] - closes[i - 1]).abs(), (lows[i] - closes[i - 1]).abs()));
    }
    final hh = highs.sublist(highs.length - period).reduce(max);
    final ll = lows.sublist(lows.length - period).reduce(min);
    if (hh == ll) return 50;
    return 100 * log(tr / (hh - ll)) / log(period);
  }

  // Klinger Volume Oscillator (simplified)
  static double? klinger(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, [int fast = 34, int slow = 55]) {
    if (closes.length < slow + 2) return null;
    final vf = <double>[];
    int trend = 0;
    for (int i = 1; i < closes.length; i++) {
      final hlc = (highs[i] + lows[i] + closes[i]) / 3;
      final prevHlc = (highs[i - 1] + lows[i - 1] + closes[i - 1]) / 3;
      if (hlc > prevHlc) {
        if (trend <= 0) trend = 1;
      } else {
        if (trend >= 0) trend = -1;
      }
      vf.add(volumes[i] * trend * (hlc - prevHlc).abs());
    }
    final e1 = emaCalc(vf, fast);
    final e2 = emaCalc(vf, slow);
    if (e1 == null || e2 == null) return null;
    return e1 - e2;
  }

  // Twiggs Money Flow (simplified)
  static double? twiggsMoneyFlow(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, [int period = 21]) {
    if (closes.length < period + 1) return null;
    double pos = 0, neg = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final trueHigh = max(highs[i], closes[i - 1]);
      final trueLow = min(lows[i], closes[i - 1]);
      final rng = trueHigh - trueLow;
      if (rng == 0) continue;
      final ad = ((closes[i] - trueLow) - (trueHigh - closes[i])) / rng * volumes[i];
      if (ad > 0) pos += ad; else neg += ad.abs();
    }
    if (neg == 0) return 100;
    return 100 - 100 / (1 + pos / neg);
  }

  // Elder Impulse System
  static String elderImpulse(List<double> closes, List<double> highs, List<double> lows, [int emaP = 13]) {
    final ema = emaCalc(closes, emaP);
    if (ema == null || closes.length < 15) return 'NEUTRAL';
    final (_, _, hist) = _macd(closes);
    if (hist == null) return 'NEUTRAL';
    final emaUp = closes.last > ema;
    final macdUp = hist > 0;
    if (emaUp && macdUp) return 'GREEN';
    if (!emaUp && !macdUp) return 'RED';
    return 'NEUTRAL';
  }

  // SMI (Stochastic Momentum Index)
  static double? smi(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period) return null;
    final hh = highs.sublist(highs.length - period).reduce(max);
    final ll = lows.sublist(lows.length - period).reduce(min);
    if (hh == ll) return 0;
    final mid = (hh + ll) / 2;
    final range = hh - ll;
    double dist = closes.last - mid;
    double emaDist = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final m = (highs[i] + lows[i]) / 2;
      emaDist += closes[i] - m;
    }
    emaDist /= period;
    return 100 * emaDist / (range / 2 + 0.001);
  }

  // Relative Vigor Index
  static double? rviVigor(List<double> opens, List<double> highs, List<double> lows, List<double> closes, [int period = 10]) {
    if (closes.length < period + 1) return null;
    double num = 0, den = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      num += closes[i] - opens[i];
      den += highs[i] - lows[i];
    }
    return den == 0 ? 0 : num / den;
  }

  // WaveTrend (LazyBear style simplified)
  static (double?, double?) waveTrend(List<double> highs, List<double> lows, List<double> closes, [int period = 10]) {
    if (closes.length < period) return (null, null);
    final ap = <double>[];
    for (int i = 0; i < closes.length; i++) ap.add((highs[i] + lows[i] + closes[i]) / 3);
    final esa = emaCalc(ap, period);
    if (esa == null) return (null, null);
    final d = <double>[];
    for (final x in ap) d.add((x - esa).abs());
    final de = emaCalc(d, period);
    if (de == null || de == 0) return (0.0, 0.0);
    final ci = (ap.last - esa) / (0.015 * de);
    return (ci, ci); // wt1, wt2 approximated
  }

  // Helpers
  static double? smaCalc(List<double> arr, int p) {
    if (arr.length < p) return null;
    double s = 0;
    for (int i = arr.length - p; i < arr.length; i++) s += arr[i];
    return s / p;
  }

  static double? emaCalc(List<double> arr, int p) {
    if (arr.length < p) return null;
    final k = 2 / (p + 1);
    double e = arr.take(p).reduce((a, b) => a + b) / p;
    for (int i = p; i < arr.length; i++) e = arr[i] * k + e * (1 - k);
    return e;
  }

  static (double?, double?, double?) _macd(List<double> closes) {
    final e12 = emaCalc(closes, 12);
    final e26 = emaCalc(closes, 26);
    if (e12 == null || e26 == null) return (null, null, null);
    final macd = e12 - e26;
    return (macd, macd, macd > 0 ? 1.0 : -1.0);
  }
}
