import 'api_candles.dart';
import 'engine.dart';
import 'advanced.dart';
import 'indicators_v2.dart';
import 'indicators_v3.dart';

class TimeframeAnalysis {
  final String interval;
  final String trend;         // BULL / BEAR / NEUTRAL
  final int bullScore;
  final int bearScore;
  final String nextCandle;    // GREEN / RED / DOJI
  final int nextConfidence;   // 0-100
  final double support;
  final double resistance;
  final double entryBuy;
  final double entrySell;
  final List<String> patterns;
  final String summary;

  TimeframeAnalysis({
    required this.interval, required this.trend,
    required this.bullScore, required this.bearScore,
    required this.nextCandle, required this.nextConfidence,
    required this.support, required this.resistance,
    required this.entryBuy, required this.entrySell,
    required this.patterns, required this.summary,
  });
}

class DeepAnalysisResult {
  final String symbol;
  final double currentPrice;
  final Map<String, TimeframeAnalysis> timeframes;
  final String overallTrend;
  final int overallBull;
  final int overallBear;
  final String recommendation;   // STRONG_BUY / BUY / WAIT / SELL / STRONG_SELL
  final double bestBuy;
  final double bestSell;
  final double stopLoss;
  final double takeProfit;
  final List<String> keyPatterns;
  final String summary;

  DeepAnalysisResult({
    required this.symbol, required this.currentPrice,
    required this.timeframes, required this.overallTrend,
    required this.overallBull, required this.overallBear,
    required this.recommendation, required this.bestBuy,
    required this.bestSell, required this.stopLoss,
    required this.takeProfit, required this.keyPatterns,
    required this.summary,
  });
}

class DeepAnalyzer {
  /// Analyze one timeframe
  static TimeframeAnalysis analyzeTimeframe(String interval, List<Kline> candles) {
    final closes = candles.map((c) => c.close).toList();
    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    final opens = candles.map((c) => c.open).toList();
    final volumes = candles.map((c) => c.volume).toList();

    int bull = 0, bear = 0;
    final patterns = <String>[];

    // 1) SMA
    final sma20 = Indicators.sma(closes, 20);
    final sma50 = Indicators.sma(closes, 50);
    if (sma20 != null && sma50 != null) {
      if (sma20 > sma50) bull += 15; else bear += 15;
    }

    // 2) EMA
    final ema12 = IndicatorsV2.emaCalc(closes, 12);
    final ema26 = IndicatorsV2.emaCalc(closes, 26);
    if (ema12 != null && ema26 != null) {
      if (ema12 > ema26) bull += 10; else bear += 10;
    }

    // 3) RSI
    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null) {
      if (rsi < 30) bull += 15;
      else if (rsi > 70) bear += 15;
      else if (rsi > 50) bull += 5;
      else bear += 5;
    }

    // 4) MACD
    final (_, __, hist) = Indicators.macd(closes);
    if (hist != null) {
      if (hist > 0) bull += 10; else bear += 10;
    }

    // 5) Bollinger
    final (bl, bm, bu) = Indicators.bollinger(closes, 20, 2);
    if (bl != null && bm != null && bu != null) {
      if (closes.last <= bl) bull += 12;
      else if (closes.last >= bu) bear += 12;
    }

    // 6) Stochastic
    final stoch = Indicators.stochastic(highs, lows, closes, 14);
    if (stoch != null) {
      if (stoch < 20) bull += 10;
      else if (stoch > 80) bear += 10;
    }

    // 7) SuperTrend
    final (_, stDir) = AdvIndicators.superTrend(highs, lows, closes, 10, 3.0);
    if (stDir == 'BUY') bull += 10; else bear += 10;

    // 8) Volume Surge
    final vs = AdvIndicators.volumeSurge(volumes, 20);
    if (vs > 1.5) {
      final up = closes.last > closes[closes.length - 2];
      if (up) bull += 8; else bear += 8;
    }

    // 9) KDJ
    final (k, d, j) = IndicatorsV2.kdj(highs, lows, closes, 9);
    if (j != null) {
      if (j < 20) bull += 8;
      else if (j > 80) bear += 8;
    }

    // 10) ADX
    final adx = _adx(highs, lows, closes, 14);
    if (adx != null && adx > 25) {
      if (ema12 != null && ema26 != null) {
        if (ema12 > ema26) bull += 5; else bear += 5;
      }
    }

    // Detect patterns
    patterns.addAll(_detectPatterns(opens, highs, lows, closes));

    // Support/Resistance
    final (support, resistance) = _findSR(closes, highs, lows, 30);

    // Next candle prediction
    final (next, confidence) = _predictNextCandle(opens, highs, lows, closes, volumes, bull, bear);

    // Trend
    String trend;
    if (bull > bear + 15) trend = 'BULL';
    else if (bear > bull + 15) trend = 'BEAR';
    else trend = 'NEUTRAL';

    // Entry/Exit zones
    final atr = _atr(highs, lows, closes, 14);
    final entryBuy = closes.last - atr * 0.5;
    final entrySell = closes.last + atr * 0.5;

    // Summary
    final summary = _tfSummary(interval, trend, rsi, next, confidence);

    return TimeframeAnalysis(
      interval: interval, trend: trend,
      bullScore: bull.clamp(0, 100), bearScore: bear.clamp(0, 100),
      nextCandle: next, nextConfidence: confidence,
      support: support, resistance: resistance,
      entryBuy: entryBuy, entrySell: entrySell,
      patterns: patterns, summary: summary,
    );
  }

  /// Full deep analysis across all timeframes
  static Future<DeepAnalysisResult?> analyze(String symbol) async {
    final tfMap = <String, TimeframeAnalysis>{};
    final intervals = ['1m', '5m', '15m', '1h'];

    for (final iv in intervals) {
      final candles = await CandleService.fetchCandles(symbol, interval: iv, limit: 100);
      if (candles == null || candles.length < 50) continue;
      tfMap[iv] = analyzeTimeframe(iv, candles);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (tfMap.isEmpty) return null;

    final last1m = await CandleService.fetchCandles(symbol, interval: '1m', limit: 5);
    final price = (last1m != null && last1m.isNotEmpty) ? last1m.last.close : 0.0;

    // Overall
    int totalBull = 0, totalBear = 0;
    for (final tf in tfMap.values) {
      totalBull += tf.bullScore;
      totalBear += tf.bearScore;
    }
    final overallBull = (totalBull / tfMap.length).round();
    final overallBear = (totalBear / tfMap.length).round();

    String overallTrend;
    if (overallBull > overallBear + 10) overallTrend = 'BULL';
    else if (overallBear > overallBull + 10) overallTrend = 'BEAR';
    else overallTrend = 'NEUTRAL';

    // Recommendation
    String rec;
    if (overallBull >= 70 && overallBear < 30) rec = 'STRONG_BUY';
    else if (overallBull >= 55) rec = 'BUY';
    else if (overallBear >= 70 && overallBull < 30) rec = 'STRONG_SELL';
    else if (overallBear >= 55) rec = 'SELL';
    else rec = 'WAIT';

    // Best buy/sell from all timeframes
    double bestBuy = double.infinity;
    double bestSell = 0;
    final allPatterns = <String>[];
    for (final tf in tfMap.values) {
      if (tf.entryBuy < bestBuy) bestBuy = tf.entryBuy;
      if (tf.entrySell > bestSell) bestSell = tf.entrySell;
      allPatterns.addAll(tf.patterns);
    }

    final atr = _atr(
      last1m?.map((c) => c.high).toList() ?? [],
      last1m?.map((c) => c.low).toList() ?? [],
      last1m?.map((c) => c.close).toList() ?? [],
      14,
    );

    final sl = price - atr * 1.5;
    final tp = price + atr * 3.0;

    // Overall summary
    final summary = _overallSummary(symbol, price, overallTrend, overallBull, overallBear, rec);

    return DeepAnalysisResult(
      symbol: symbol, currentPrice: price,
      timeframes: tfMap, overallTrend: overallTrend,
      overallBull: overallBull, overallBear: overallBear,
      recommendation: rec, bestBuy: bestBuy,
      bestSell: bestSell, stopLoss: sl, takeProfit: tp,
      keyPatterns: allPatterns.toSet().toList(),
      summary: summary,
    );
  }

  // ============ CANDLE PREDICTION ============
  static (String, int) _predictNextCandle(
    List<double> opens, List<double> highs, List<double> lows,
    List<double> closes, List<double> volumes,
    int bull, int bear,
  ) {
    if (closes.length < 5) return ('DOJI', 30);

    int score = 0;

    // Momentum of last 3 candles
    final last3 = closes.sublist(closes.length - 3);
    double mo = 0;
    for (int i = 1; i < last3.length; i++) {
      mo += (last3[i] - last3[i - 1]) / last3[i - 1];
    }
    if (mo > 0.002) score += 20;
    else if (mo < -0.002) score -= 20;

    // Body of last candle
    final body = closes.last - opens.last;
    final range = highs.last - lows.last;
    if (range > 0) {
      final bodyPct = body.abs() / range;
      if (bodyPct > 0.6) {
        if (body > 0) score += 15; else score -= 15;
      }
    }

    // Volume trend
    final vs = AdvIndicators.volumeSurge(volumes, 20);
    if (vs > 1.3) {
      if (body > 0) score += 15; else score -= 15;
    }

    // RSI
    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null) {
      if (rsi < 30) score += 20;
      else if (rsi > 70) score -= 20;
      else if (rsi > 55) score += 5;
      else if (rsi < 45) score -= 5;
    }

    // Bull/Bear score
    score += (bull - bear) ~/ 5;

    String next;
    int conf;
    if (score > 20) {
      next = 'GREEN';
      conf = (50 + score).clamp(50, 95);
    } else if (score < -20) {
      next = 'RED';
      conf = (50 + score.abs()).clamp(50, 95);
    } else {
      next = 'DOJI';
      conf = 40;
    }
    return (next, conf);
  }

  // ============ PATTERN DETECTION ============
  static List<String> _detectPatterns(
    List<double> opens, List<double> highs, List<double> lows, List<double> closes,
  ) {
    final out = <String>[];
    if (closes.length < 5) return out;
    final n = closes.length;

    // Last 3 candles
    final o1 = opens[n-3], h1 = highs[n-3], l1 = lows[n-3], c1 = closes[n-3];
    final o2 = opens[n-2], h2 = highs[n-2], l2 = lows[n-2], c2 = closes[n-2];
    final o3 = opens[n-1], h3 = highs[n-1], l3 = lows[n-1], c3 = closes[n-1];

    double body(double o, double c) => (c - o).abs();
    double range(double h, double l) => h - l;

    // Doji
    if (range(h3, l3) > 0 && body(o3, c3) / range(h3, l3) < 0.1) {
      out.add('Doji 🕯️');
    }

    // Hammer
    final lower3 = (o3 < c3 ? o3 : c3) - l3;
    final upper3 = h3 - (o3 > c3 ? o3 : c3);
    if (lower3 > body(o3, c3) * 2 && upper3 < body(o3, c3) * 0.5) {
      out.add('Hammer 🔨');
    }

    // Shooting star
    if (upper3 > body(o3, c3) * 2 && lower3 < body(o3, c3) * 0.5) {
      out.add('Shooting Star ⭐');
    }

    // Bullish engulfing
    if (c2 < o2 && c3 > o3 && c3 > o2 && o3 < c2) {
      out.add('Bullish Engulfing 🟢');
    }

    // Bearish engulfing
    if (c2 > o2 && c3 < o3 && c3 < o2 && o3 > c2) {
      out.add('Bearish Engulfing 🔴');
    }

    // Three white soldiers
    if (c1 > o1 && c2 > o2 && c3 > o3 && c2 > c1 && c3 > c2) {
      out.add('Three White Soldiers ⬆️');
    }

    // Three black crows
    if (c1 < o1 && c2 < o2 && c3 < o3 && c2 < c1 && c3 < c2) {
      out.add('Three Black Crows ⬇️');
    }

    // Marubozu
    if (body(o3, c3) / range(h3, l3).clamp(0.0001, double.infinity) > 0.9) {
      if (c3 > o3) out.add('Bullish Marubozu 💚');
      else out.add('Bearish Marubozu ❤️');
    }

    return out;
  }

  // ============ SUPPORT/RESISTANCE ============
  static (double, double) _findSR(
    List<double> closes, List<double> highs, List<double> lows, int lookback,
  ) {
    if (closes.length < lookback) lookback = closes.length;
    final recentHighs = highs.sublist(highs.length - lookback);
    final recentLows = lows.sublist(lows.length - lookback);
    final res = recentHighs.reduce((a, b) => a > b ? a : b);
    final sup = recentLows.reduce((a, b) => a < b ? a : b);
    return (sup, res);
  }

  // ============ ATR ============
  static double _atr(List<double> highs, List<double> lows, List<double> closes, int period) {
    if (closes.length < period + 1) return 0;
    double sum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final tr = [
        highs[i] - lows[i],
        (highs[i] - closes[i-1]).abs(),
        (lows[i] - closes[i-1]).abs(),
      ].reduce((a, b) => a > b ? a : b);
      sum += tr;
    }
    return sum / period;
  }

  static double? _adx(List<double> h, List<double> l, List<double> c, int p) {
    if (c.length < p + 2) return null;
    double atr = 0, pdm = 0, ndm = 0;
    for (int i = c.length - p; i < c.length; i++) {
      atr += (h[i] - l[i]).abs();
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

  static String _tfSummary(String interval, String trend, double? rsi, String next, int conf) {
    final r = rsi?.toStringAsFixed(0) ?? '--';
    final t = trend == 'BULL' ? 'صاعد 📈' : trend == 'BEAR' ? 'هابط 📉' : 'عرضي ➡️';
    final n = next == 'GREEN' ? 'خضراء 🟢' : next == 'RED' ? 'حمراء 🔴' : 'دوجي 🕯️';
    return '[$interval] $t | RSI:$r | الشمعة القادمة: $n ($conf%)';
  }

  static String _overallSummary(String sym, double price, String trend, int bull, int bear, String rec) {
    final t = trend == 'BULL' ? 'صاعد 📈' : trend == 'BEAR' ? 'هابط 📉' : 'عرضي ➡️';
    final r = rec == 'STRONG_BUY' ? 'شراء قوي 🚀'
        : rec == 'BUY' ? 'شراء 🟢'
        : rec == 'STRONG_SELL' ? 'بيع قوي 🔻'
        : rec == 'SELL' ? 'بيع 🔴'
        : 'انتظار ⏸️';
    return 'العملة: $sym\nالسعر: \$${price.toStringAsFixed(4)}\nالاتجاه العام: $t\nقوة الصعود: $bull/100 | قوة الهبوط: $bear/100\nالتوصية: $r';
  }
}
