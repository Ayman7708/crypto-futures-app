import 'dart:math';

class VolatilityScore {
  final String symbol;
  final double atrPct;       // ATR as % of price
  final double volumeSurge;  // Current vol / avg vol
  final double momentum1h;   // % change
  final double rangePct;     // High-low range %
  final double opportunity;  // Composite 0-100
  final String rank;         // FAST, MEDIUM, SLOW, DEAD

  VolatilityScore({
    required this.symbol,
    required this.atrPct,
    required this.volumeSurge,
    required this.momentum1h,
    required this.rangePct,
    required this.opportunity,
    required this.rank,
  });
}

class VolatilityRanker {
  static VolatilityScore analyze({
    required String symbol,
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required List<double> volumes,
  }) {
    if (closes.length < 20) {
      return VolatilityScore(
        symbol: symbol,
        atrPct: 0, volumeSurge: 1, momentum1h: 0,
        rangePct: 0, opportunity: 0, rank: 'DEAD',
      );
    }

    // ATR (14)
    double atrSum = 0;
    for (int i = closes.length - 14; i < closes.length; i++) {
      final h = highs[i], l = lows[i], pc = closes[i - 1];
      atrSum += max(h - l, max((h - pc).abs(), (l - pc).abs()));
    }
    final atr = atrSum / 14;
    final atrPct = closes.last > 0 ? (atr / closes.last * 100) : 0.0;

    // Volume surge
    double avgVol = 0;
    for (int i = volumes.length - 21; i < volumes.length - 1; i++) {
      avgVol += volumes[i];
    }
    avgVol /= 20;
    final vs = avgVol > 0 ? volumes.last / avgVol : 1.0;

    // Momentum over last 20 candles
    final startPrice = closes[closes.length - 20];
    final momentum = startPrice > 0
        ? (closes.last - startPrice) / startPrice * 100
        : 0.0;

    // Range
    final maxH = highs.sublist(highs.length - 20).reduce(max);
    final minL = lows.sublist(lows.length - 20).reduce(min);
    final rangePct = minL > 0 ? (maxH - minL) / minL * 100 : 0.0;

    // Composite opportunity score
    // Weight: ATR% (fast movement), volume (activity), |momentum| (trend), range
    double score = 0;
    score += (atrPct * 8).clamp(0, 40).toDouble();         // ATR is key
    score += ((vs - 1) * 15).clamp(0, 25).toDouble();      // Volume surge
    score += (momentum.abs() * 2).clamp(0, 20).toDouble(); // Any direction momentum
    score += (rangePct * 1.2).clamp(0, 15).toDouble();     // Range

    final opp = score.clamp(0, 100).toDouble();

    // Rank
    String rank;
    if (opp >= 65) rank = 'FAST';
    else if (opp >= 45) rank = 'MEDIUM';
    else if (opp >= 25) rank = 'SLOW';
    else rank = 'DEAD';

    return VolatilityScore(
      symbol: symbol,
      atrPct: atrPct,
      volumeSurge: vs,
      momentum1h: momentum,
      rangePct: rangePct,
      opportunity: opp,
      rank: rank,
    );
  }

  // Return top N symbols sorted by opportunity
  static List<String> topSymbols(
    Map<String, VolatilityScore> scores,
    int n,
  ) {
    final list = scores.values.toList();
    list.sort((a, b) => b.opportunity.compareTo(a.opportunity));
    return list.take(n).map((s) => s.symbol).toList();
  }

  static String rankEmoji(String rank) {
    switch (rank) {
      case 'FAST': return '🔥';
      case 'MEDIUM': return '⚡';
      case 'SLOW': return '💤';
      default: return '❄️';
    }
  }
}
