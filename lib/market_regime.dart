import 'dart:math';

enum Regime { bullStrong, bullWeak, neutral, bearWeak, bearStrong }

class MarketAnalysis {
  final Regime regime;
  final double btcTrendPct;
  final double altTrendPct;
  final double altseasonScore; // -100 to +100
  final double btcDominanceProxy; // higher = BTC leading
  final String description;

  MarketAnalysis({
    required this.regime,
    required this.btcTrendPct,
    required this.altTrendPct,
    required this.altseasonScore,
    required this.btcDominanceProxy,
    required this.description,
  });
}

class MarketRegimeAnalyzer {
  static MarketAnalysis analyze({
    required List<double> btcCloses,
    required Map<String, List<double>> altCloses,
  }) {
    if (btcCloses.length < 50) {
      return MarketAnalysis(
        regime: Regime.neutral,
        btcTrendPct: 0.0, altTrendPct: 0.0, altseasonScore: 0.0,
        btcDominanceProxy: 0.0, description: 'بيانات غير كافية',
      );
    }

    // BTC trend over last 30 candles
    final btcStart = btcCloses[btcCloses.length - 30];
    final btcTrend = (btcCloses.last - btcStart) / btcStart * 100;

    // BTC SMA20 vs SMA50
    final sma20 = _sma(btcCloses, 20);
    final sma50 = _sma(btcCloses, 50);
    final smaBullish = sma20 != null && sma50 != null && sma20 > sma50;

    // Altcoins trend (average)
    double altTrendSum = 0;
    int altCount = 0;
    for (final entry in altCloses.entries) {
      final closes = entry.value;
      if (closes.length < 30) continue;
      final start = closes[closes.length - 30];
      if (start == 0) continue;
      altTrendSum += (closes.last - start) / start * 100;
      altCount++;
    }
    final altTrend = altCount > 0 ? altTrendSum / altCount : 0.0;

    // Altseason score: alts outperforming BTC = positive
    final altseason = ((altTrend - btcTrend).clamp(-100.0, 100.0)).toDouble();

    // BTC dominance proxy: BTC vs alts
    final dominanceProxy = ((btcTrend - altTrend).clamp(-100.0, 100.0)).toDouble();

    // Classify regime
    Regime regime;
    String desc;
    if (smaBullish && btcTrend > 3) {
      regime = Regime.bullStrong;
      desc = '🐂 صاعد قوي — تكثيف الشراء';
    } else if (smaBullish) {
      regime = Regime.bullWeak;
      desc = '📈 صاعد — تفضيل الشراء';
    } else if (!smaBullish && btcTrend < -3) {
      regime = Regime.bearStrong;
      desc = '🐻 هابط قوي — تكثيف البيع';
    } else if (!smaBullish) {
      regime = Regime.bearWeak;
      desc = '📉 هابط — تفضيل البيع';
    } else {
      regime = Regime.neutral;
      desc = '➡️ عرضي — تداول الاتجاهين';
    }

    return MarketAnalysis(
      regime: regime,
      btcTrendPct: btcTrend,
      altTrendPct: altTrend,
      altseasonScore: altseason,
      btcDominanceProxy: dominanceProxy,
      description: desc,
    );
  }

  static double? _sma(List<double> arr, int p) {
    if (arr.length < p) return null;
    double s = 0;
    for (int i = arr.length - p; i < arr.length; i++) s += arr[i];
    return s / p;
  }

  static String regimeName(Regime r) {
    switch (r) {
      case Regime.bullStrong: return 'صاعد قوي';
      case Regime.bullWeak: return 'صاعد';
      case Regime.neutral: return 'عرضي';
      case Regime.bearWeak: return 'هابط';
      case Regime.bearStrong: return 'هابط قوي';
    }
  }

  // Returns (longMultiplier, shortMultiplier, thresholdAdjust)
  static (double, double, int) tradingBias(Regime r, double altseason) {
    switch (r) {
      case Regime.bullStrong:
        return (1.5, 0.3, -10);
      case Regime.bullWeak:
        return (1.3, 0.6, -5);
      case Regime.neutral:
        return (1.0, 1.0, 0);
      case Regime.bearWeak:
        return (0.6, 1.3, -5);
      case Regime.bearStrong:
        return (0.3, 1.5, -10);
    }
  }
}
