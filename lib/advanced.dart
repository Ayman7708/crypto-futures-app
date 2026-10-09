import 'dart:math';
import 'engine.dart';

// ============= ADVANCED INDICATORS =============
class AdvIndicators {
  static double? ema(List<double> arr, int period) {
    if (arr.length < period) return null;
    final k = 2 / (period + 1);
    double e = arr.take(period).reduce((a, b) => a + b) / period;
    for (int i = period; i < arr.length; i++) {
      e = arr[i] * k + e * (1 - k);
    }
    return e;
  }

  static double? adx(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period + 2) return null;
    double atr = 0, plusDM = 0, minusDM = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final h = highs[i], l = lows[i], pc = closes[i - 1];
      atr += max(h - l, max((h - pc).abs(), (l - pc).abs()));
      final up = highs[i] - highs[i - 1];
      final dn = lows[i - 1] - lows[i];
      if (up > dn && up > 0) plusDM += up;
      if (dn > up && dn > 0) minusDM += dn;
    }
    if (atr == 0) return 0;
    final plusDI = 100 * plusDM / atr;
    final minusDI = 100 * minusDM / atr;
    final sum = plusDI + minusDI;
    if (sum == 0) return 0;
    return (plusDI - minusDI).abs() / sum * 100;
  }

  static double? vwap(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, [int period = 20]) {
    if (closes.length < period) return null;
    double spv = 0, sv = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final tp = (highs[i] + lows[i] + closes[i]) / 3;
      spv += tp * volumes[i];
      sv += volumes[i];
    }
    return sv == 0 ? null : spv / sv;
  }

  static (double?, String) superTrend(List<double> highs, List<double> lows, List<double> closes, [int period = 10, double mult = 3]) {
    if (closes.length < period + 1) return (null, 'NEUTRAL');
    double trSum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      trSum += max(highs[i] - lows[i], max((highs[i] - closes[i - 1]).abs(), (lows[i] - closes[i - 1]).abs()));
    }
    final atr = trSum / period;
    final hl2 = (highs.last + lows.last) / 2;
    final upper = hl2 + mult * atr;
    final lower = hl2 - mult * atr;
    final st = closes.last > lower ? lower : upper;
    return (st, closes.last > st ? 'BUY' : 'SELL');
  }

  static (double?, double?, double?) ichimoku(List<double> highs, List<double> lows) {
    if (highs.length < 52) return (null, null, null);
    double hh(int p) => highs.sublist(highs.length - p).reduce(max);
    double ll(int p) => lows.sublist(lows.length - p).reduce(min);
    final tenkan = (hh(9) + ll(9)) / 2;
    final kijun = (hh(26) + ll(26)) / 2;
    final senkouA = (tenkan + kijun) / 2;
    final senkouB = (hh(52) + ll(52)) / 2;
    return (senkouA, senkouB, kijun);
  }

  static double? williamsR(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period) return null;
    final hh = highs.sublist(highs.length - period).reduce(max);
    final ll = lows.sublist(lows.length - period).reduce(min);
    if (hh == ll) return -50;
    return -100 * (hh - closes.last) / (hh - ll);
  }

  static double? cci(List<double> highs, List<double> lows, List<double> closes, [int period = 20]) {
    if (closes.length < period) return null;
    final tps = List<double>.generate(closes.length, (i) => (highs[i] + lows[i] + closes[i]) / 3);
    final slice = tps.sublist(tps.length - period);
    final sma = slice.reduce((a, b) => a + b) / period;
    double dev = 0;
    for (final v in slice) dev += (v - sma).abs();
    final md = dev / period;
    if (md == 0) return 0;
    return (tps.last - sma) / (0.015 * md);
  }

  static double? mfi(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, [int period = 14]) {
    if (closes.length < period + 1) return null;
    double pos = 0, neg = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final tp = (highs[i] + lows[i] + closes[i]) / 3;
      final ptp = (highs[i - 1] + lows[i - 1] + closes[i - 1]) / 3;
      final mf = tp * volumes[i];
      if (tp > ptp) pos += mf; else neg += mf;
    }
    if (neg == 0) return 100;
    return 100 - (100 / (1 + pos / neg));
  }

  static double? roc(List<double> closes, [int period = 10]) {
    if (closes.length < period + 1) return null;
    final past = closes[closes.length - period - 1];
    if (past == 0) return 0;
    return (closes.last - past) / past * 100;
  }

  static (double?, double?, double?) keltner(List<double> highs, List<double> lows, List<double> closes, [int period = 20, double mult = 2]) {
    final e = ema(closes, period);
    if (e == null || closes.length < period) return (null, null, null);
    double trSum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      trSum += max(highs[i] - lows[i], max((highs[i] - closes[i - 1]).abs(), (lows[i] - closes[i - 1]).abs()));
    }
    final atr = trSum / period;
    return (e - mult * atr, e, e + mult * atr);
  }

  static double? obvTrend(List<double> closes, List<double> volumes, [int period = 20]) {
    if (closes.length < period + 1) return null;
    final obvs = <double>[];
    double obv = 0;
    for (int i = 1; i < closes.length; i++) {
      if (closes[i] > closes[i - 1]) obv += volumes[i];
      else if (closes[i] < closes[i - 1]) obv -= volumes[i];
      obvs.add(obv);
    }
    if (obvs.length < period) return null;
    final recent = obvs.sublist(obvs.length - period);
    return recent.last - recent[period ~/ 2];
  }

  static double volumeSurge(List<double> volumes, [int period = 20]) {
    if (volumes.length < period + 1) return 1.0;
    final avg = volumes.sublist(volumes.length - period - 1, volumes.length - 1).reduce((a, b) => a + b) / period;
    if (avg == 0) return 1.0;
    return volumes.last / avg;
  }

  static double? rsiDivergence(List<double> closes, [int period = 14]) {
    if (closes.length < period * 2) return null;
    final rsi = Indicators.rsi(closes, period);
    if (rsi == null) return null;
    final recentLow = closes.sublist(closes.length - 10).reduce(min);
    final prevLow = closes.sublist(closes.length - 20, closes.length - 10).reduce(min);
    if (recentLow < prevLow && rsi > 40) return 1;
    if (recentLow > prevLow && rsi < 60) return -1;
    return 0;
  }

  static double? bollingerSqueeze(List<double> closes, [int period = 20, double mult = 2]) {
    final (low, mid, up) = Indicators.bollinger(closes, period, mult);
    if (low == null || mid == null || up == null) return null;
    if (mid == 0) return null;
    final width = (up - low) / mid;
    return width;
  }
}

// ============= INDICATOR REGISTRY =============
class IndicatorDef {
  final String id;
  final String name;
  final String platform;
  final String category;
  int tests;
  int wins;
  int losses;
  bool approved;
  double weight;
  IndicatorDef({
    required this.id, required this.name, required this.platform,
    required this.category, this.tests = 0, this.wins = 0, this.losses = 0,
    this.approved = false, this.weight = 1.0,
  });
  double get winRate => tests == 0 ? 0 : (wins / tests * 100);
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'platform': platform, 'category': category,
    'tests': tests, 'wins': wins, 'losses': losses,
    'approved': approved, 'weight': weight,
  };
  factory IndicatorDef.fromJson(Map<String, dynamic> j) => IndicatorDef(
    id: j['id'], name: j['name'], platform: j['platform'], category: j['category'],
    tests: j['tests'] ?? 0, wins: j['wins'] ?? 0, losses: j['losses'] ?? 0,
    approved: j['approved'] ?? false, weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
  );
}

class IndicatorRegistry {
  static List<IndicatorDef> defaults() => [
    IndicatorDef(id: 'sma_cross', name: 'SMA Crossover', platform: 'Universal', category: 'Trend'),
    IndicatorDef(id: 'ema_cross', name: 'EMA Crossover', platform: 'Universal', category: 'Trend'),
    IndicatorDef(id: 'rsi', name: 'RSI', platform: 'Universal', category: 'Momentum'),
    IndicatorDef(id: 'macd', name: 'MACD', platform: 'Universal', category: 'Momentum'),
    IndicatorDef(id: 'bollinger', name: 'Bollinger Bands', platform: 'Universal', category: 'Volatility'),
    IndicatorDef(id: 'stoch', name: 'Stochastic', platform: 'Universal', category: 'Momentum'),
    IndicatorDef(id: 'adx', name: 'ADX', platform: 'TradingView', category: 'Trend'),
    IndicatorDef(id: 'vwap', name: 'VWAP', platform: 'TradingView', category: 'Volume'),
    IndicatorDef(id: 'super_trend', name: 'SuperTrend', platform: 'TradingView', category: 'Trend'),
    IndicatorDef(id: 'ichimoku', name: 'Ichimoku Cloud', platform: 'TradingView', category: 'Trend'),
    IndicatorDef(id: 'williams_r', name: 'Williams %R', platform: 'TradingView', category: 'Momentum'),
    IndicatorDef(id: 'cci', name: 'CCI', platform: 'TradingView', category: 'Momentum'),
    IndicatorDef(id: 'mfi', name: 'MFI', platform: 'TradingView', category: 'Volume'),
    IndicatorDef(id: 'roc', name: 'Rate of Change', platform: 'TradingView', category: 'Momentum'),
    IndicatorDef(id: 'keltner', name: 'Keltner Channel', platform: 'TradingView', category: 'Volatility'),
    IndicatorDef(id: 'obv', name: 'OBV Trend', platform: 'TradingView', category: 'Volume'),
    IndicatorDef(id: 'volume_surge', name: 'Volume Surge', platform: 'Universal', category: 'Volume'),
    IndicatorDef(id: 'divergence', name: 'RSI Divergence', platform: 'TradingView', category: 'Reversal'),
    IndicatorDef(id: 'squeeze', name: 'BB Squeeze', platform: 'TradingView', category: 'Volatility'),
    IndicatorDef(id: 'lux_algo', name: 'LuxAlgo Premium', platform: 'TradingView', category: 'Smart Money'),
    IndicatorDef(id: 'order_block', name: 'Order Block Scanner', platform: 'TradingView', category: 'ICT'),
    IndicatorDef(id: 'market_ci', name: 'Market Cipher B', platform: 'TradingView', category: 'Momentum'),
    IndicatorDef(id: 'pmax', name: 'PMax Explorer', platform: 'TradingView', category: 'Trend'),
    IndicatorDef(id: 'ut_bot', name: 'UT Bot Alerts', platform: 'TradingView', category: 'Trend'),
    IndicatorDef(id: 'vp', name: 'Volume Profile', platform: 'TradingView', category: 'Volume'),
  ];
}

// ============= LEARNING ENGINE =============
class LearningEngine {
  static void updateWeights(List<IndicatorDef> indicators, List<TradeRecord> trades) {
    if (trades.isEmpty) return;
    for (final ind in indicators) {
      if (ind.tests < 3) continue;
      final wr = ind.winRate;
      if (wr >= 65) {
        ind.weight = min(2.0, ind.weight * 1.05).toDouble();
      } else if (wr < 45) {
        ind.weight = max(0.3, ind.weight * 0.95).toDouble();
      }
      ind.approved = ind.tests >= 5 && wr >= 55;
    }
  }

  static int adaptiveThreshold(List<TradeRecord> trades, int base) {
    if (trades.length < 5) return base;
    final recent = trades.take(20).toList();
    int wins = 0, closed = 0;
    for (final t in recent) {
      if (['SELL', 'TAKE_PROFIT', 'STOP_LOSS', 'LIQUIDATED'].contains(t.action)) {
        closed++;
        if (t.pnl > 0) wins++;
      }
    }
    if (closed < 3) return base;
    final wr = wins / closed * 100;
    if (wr >= 60) return max(40, base - 5).toInt();
    if (wr < 40) return min(85, base + 10).toInt();
    return base;
  }
}

// ============= PUMP SCANNER =============
class PumpScanner {
  static double pumpProbability({
    required List<double> closes,
    required List<double> volumes,
    required List<double> highs,
    required List<double> lows,
  }) {
    if (closes.length < 30) return 0;
    double score = 0;

    final vs = AdvIndicators.volumeSurge(volumes, 20);
    if (vs > 2.0) score += 30;
    else if (vs > 1.5) score += 20;
    else if (vs > 1.2) score += 10;

    final (low, mid, up) = Indicators.bollinger(closes, 20, 2);
    if (low != null && mid != null && up != null && mid != 0) {
      final width = (up - low) / mid;
      if (width < 0.02) score += 20;
      else if (width < 0.04) score += 10;
    }

    if (closes.length >= 20) {
      final h1 = closes.sublist(closes.length - 10).reduce(min);
      final h2 = closes.sublist(closes.length - 20, closes.length - 10).reduce(min);
      if (h1 > h2) score += 20;
    }

    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null && rsi > 30 && rsi < 50) score += 15;

    final (macd, sig, hist) = Indicators.macd(closes);
    if (hist != null && hist > 0 && macd! > sig!) score += 15;

    return score.clamp(0, 100);
  }
}

// ============= ADVANCED SIGNAL =============
class AdvancedSignal {
  final String direction;
  final int score;
  final String reason;
  final double pumpProb;
  AdvancedSignal(this.direction, this.score, this.reason, this.pumpProb);
}

class AdvancedAnalyzer {
  static AdvancedSignal analyze({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required List<double> volumes,
    required int smaShort,
    required int smaLong,
    required int rsiBuy,
    required int rsiSell,
    required int pumpMinScore,
    required int scalpMinScore,
  }) {
    if (closes.length < 50) return AdvancedSignal('NONE', 0, 'Not enough data', 0);

    int score = 0;
    final r = <String>[];

    final pump = PumpScanner.pumpProbability(closes: closes, volumes: volumes, highs: highs, lows: lows);
    if (pump >= pumpMinScore) { score += 25; r.add('Pump:${pump.toInt()}%'); }
    else if (pump >= pumpMinScore - 20) { score += 10; }

    final ss = Indicators.sma(closes, smaShort);
    final sl = Indicators.sma(closes, smaLong);
    final e12 = AdvIndicators.ema(closes, 12);
    final e26 = AdvIndicators.ema(closes, 26);
    if (ss != null && sl != null && ss > sl) { score += 10; r.add('SMA'); }
    if (e12 != null && e26 != null && e12 > e26) { score += 10; r.add('EMA'); }

    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null) {
      if (rsi < 30) { score += 15; r.add('RSI-OS'); }
      else if (rsi < 55) { score += 10; r.add('RSI'); }
      else if (rsi < 70) { score += 5; }
    }

    final (macd, sig, hist) = Indicators.macd(closes);
    if (hist != null && macd != null && sig != null) {
      if (hist > 0 && macd > sig) { score += 15; r.add('MACD+'); }
      else if (macd > sig) { score += 8; }
    }

    final (bL, bM, bU) = Indicators.bollinger(closes, 20, 2);
    if (bL != null && bM != null && bU != null) {
      if (closes.last <= bL) { score += 10; r.add('BB-low'); }
      else if (closes.last < bM) { score += 5; }
    }

    final stoch = Indicators.stochastic(highs, lows, closes, 14);
    if (stoch != null && stoch < 30) { score += 10; r.add('Stoch'); }

    final wr = AdvIndicators.williamsR(highs, lows, closes, 14);
    if (wr != null && wr < -70) { score += 5; r.add('W%R'); }

    final cci = AdvIndicators.cci(highs, lows, closes, 20);
    if (cci != null && cci < -100) { score += 5; r.add('CCI'); }

    final mfi = AdvIndicators.mfi(highs, lows, closes, volumes, 14);
    if (mfi != null && mfi < 30) { score += 5; r.add('MFI'); }

    final (_, st) = AdvIndicators.superTrend(highs, lows, closes, 10, 3.0);
    if (st == 'BUY') { score += 5; r.add('ST'); }

    final (sa, sb, _) = AdvIndicators.ichimoku(highs, lows);
    if (sa != null && sb != null && closes.last > sa && closes.last > sb) {
      score += 5; r.add('Ichi');
    }

    final vs = AdvIndicators.volumeSurge(volumes, 20);
    if (vs > 1.5) { score += 5; r.add('Vol:${vs.toStringAsFixed(1)}x'); }

    final div = AdvIndicators.rsiDivergence(closes, 14);
    if (div != null && div > 0) { score += 5; r.add('Div'); }

    final adx = AdvIndicators.adx(highs, lows, closes, 14);
    if (adx != null && adx > 25) { score += 5; r.add('ADX'); }

    final vwap = AdvIndicators.vwap(highs, lows, closes, volumes, 20);
    if (vwap != null && closes.last > vwap) { score += 5; r.add('VWAP'); }

    final finalScore = score.clamp(0, 100);
    final dir = finalScore >= scalpMinScore ? 'LONG' : 'NONE';
    return AdvancedSignal(dir, finalScore, r.join(' | '), pump);
  }
}
