import 'dart:convert';
import 'dart:math';
import 'engine.dart';

enum MarketRegime { trendingUp, trendingDown, ranging, volatile, unknown }

class IndicatorPerf {
  String id;
  int wins;
  int losses;
  double weight;
  int consecutiveLosses;
  IndicatorPerf({
    required this.id, this.wins = 0, this.losses = 0,
    this.weight = 1.0, this.consecutiveLosses = 0,
  });
  double get winRate => (wins + losses) == 0 ? 0.5 : wins / (wins + losses);
  Map<String, dynamic> toJson() => {
    'id': id, 'wins': wins, 'losses': losses,
    'weight': weight, 'consecutiveLosses': consecutiveLosses,
  };
  factory IndicatorPerf.fromJson(Map<String, dynamic> j) => IndicatorPerf(
    id: j['id'], wins: j['wins'] ?? 0, losses: j['losses'] ?? 0,
    weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
    consecutiveLosses: j['consecutiveLosses'] ?? 0,
  );
}

class LosingPattern {
  String pattern;    // e.g. "RANGING|rsi>70"
  int occurrences;   // how many times this lost
  DateTime lastSeen;
  LosingPattern({required this.pattern, this.occurrences = 1, DateTime? lastSeen})
      : lastSeen = lastSeen ?? DateTime.now();
  Map<String, dynamic> toJson() => {
    'pattern': pattern, 'occurrences': occurrences,
    'lastSeen': lastSeen.toIso8601String(),
  };
  factory LosingPattern.fromJson(Map<String, dynamic> j) => LosingPattern(
    pattern: j['pattern'], occurrences: j['occurrences'] ?? 1,
    lastSeen: DateTime.tryParse(j['lastSeen'] ?? '') ?? DateTime.now(),
  );
}

class LearningEngineV2 {
  MarketRegime regime = MarketRegime.unknown;
  final Map<String, IndicatorPerf> perfs = {};
  final Map<String, LosingPattern> losingPatterns = {};
  double entryThreshold = 55.0;     // adaptive
  int totalTrades = 0;
  int totalWins = 0;
  int totalLosses = 0;
  double rollingPnL = 0.0;

  LearningEngineV2() {
    for (final id in _allIds) {
      perfs[id] = IndicatorPerf(id: id);
    }
  }

  static const _allIds = [
    'sma', 'ema', 'rsi', 'macd', 'bollinger', 'stoch', 'adx',
    'vwap', 'supertrend', 'ichimoku', 'williams', 'cci', 'mfi',
    'volume_surge', 'divergence', 'pump',
  ];

  // ============ Regime Detection ============
  void detectRegime({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
  }) {
    if (closes.length < 30) { regime = MarketRegime.unknown; return; }
    // ADX-like: use range expansion
    final recent = closes.sublist(closes.length - 20);
    final returns = <double>[];
    for (int i = 1; i < recent.length; i++) {
      returns.add((recent[i] - recent[i-1]) / recent[i-1]);
    }
    final meanRet = returns.reduce((a, b) => a + b) / returns.length;
    double variance = 0;
    for (final r in returns) variance += pow(r - meanRet, 2);
    variance /= returns.length;
    final vol = sqrt(variance);

    final trend = (recent.last - recent.first) / recent.first;

    if (vol > 0.015) {
      regime = MarketRegime.volatile;
    } else if (trend > 0.005) {
      regime = MarketRegime.trendingUp;
    } else if (trend < -0.005) {
      regime = MarketRegime.trendingDown;
    } else {
      regime = MarketRegime.ranging;
    }
  }

  String get regimeName {
    switch (regime) {
      case MarketRegime.trendingUp: return 'صاعد';
      case MarketRegime.trendingDown: return 'هابط';
      case MarketRegime.ranging: return 'عرضي';
      case MarketRegime.volatile: return 'متقلب';
      default: return 'غير معروف';
    }
  }

  // ============ Pattern key from signal ============
  String patternKey(String signalReason, String direction) {
    final parts = signalReason.split('|').map((e) => e.trim()).toList();
    final top = parts.take(3).join('+');
    return '${regime.name}|$direction|$top';
  }

  // ============ Should we enter? ============
  bool shouldEnter(int rawScore) {
    // Check if similar pattern has lost too many times
    final key = '${regime.name}';
    final bad = losingPatterns.values.where(
      (p) => p.pattern.startsWith(key) && p.occurrences >= 3
    ).length;
    // If regime has many bad patterns, be more careful
    final adjusted = rawScore - bad * 3;
    return adjusted >= entryThreshold;
  }

  // ============ Update from closed trade ============
  void updateFromTrade({
    required bool wasWin,
    required double pnl,
    required String signalReason,
    required String direction,
    required Set<String> activeIndicators,
  }) {
    totalTrades++;
    rollingPnL += pnl;
    if (wasWin) totalWins++; else totalLosses++;

    // Update each indicator weight
    for (final id in activeIndicators) {
      final p = perfs[id];
      if (p == null) continue;
      if (wasWin) {
        p.wins++;
        p.consecutiveLosses = 0;
        p.weight = min(2.5, p.weight * 1.08);
      } else {
        p.losses++;
        p.consecutiveLosses++;
        p.weight = max(0.2, p.weight * 0.90);
      }
    }

    // Track losing patterns
    if (!wasWin) {
      final key = patternKey(signalReason, direction);
      if (losingPatterns.containsKey(key)) {
        losingPatterns[key]!.occurrences++;
        losingPatterns[key]!.lastSeen = DateTime.now();
      } else {
        losingPatterns[key] = LosingPattern(pattern: key);
      }
    }

    // Adjust entry threshold based on rolling performance
    if (totalTrades >= 5) {
      final wr = totalWins / totalTrades;
      if (wr < 0.35) {
        // losing heavily → tighten (accept fewer, better trades)
        entryThreshold = min(85.0, entryThreshold + 2.0);
      } else if (wr > 0.60) {
        // winning → loosen slightly to take more trades
        entryThreshold = max(40.0, entryThreshold - 1.0);
      }
    }
  }

  // ============ Get recommended weights ============
  Map<String, double> getWeights() {
    final m = <String, double>{};
    perfs.forEach((k, v) => m[k] = v.weight);
    return m;
  }

  // ============ Best indicators by performance ============
  List<IndicatorPerf> getTopIndicators({int limit = 5}) {
    final list = perfs.values.where((p) => p.wins + p.losses >= 3).toList();
    list.sort((a, b) => b.winRate.compareTo(a.winRate));
    return list.take(limit).toList();
  }

  List<IndicatorPerf> getWorstIndicators({int limit = 5}) {
    final list = perfs.values.where((p) => p.wins + p.losses >= 3).toList();
    list.sort((a, b) => a.winRate.compareTo(b.winRate));
    return list.take(limit).toList();
  }

  // ============ Serialization ============
  Map<String, dynamic> toJson() => {
    'regime': regime.name,
    'entryThreshold': entryThreshold,
    'totalTrades': totalTrades,
    'totalWins': totalWins,
    'totalLosses': totalLosses,
    'rollingPnL': rollingPnL,
    'perfs': perfs.map((k, v) => MapEntry(k, v.toJson())),
    'losingPatterns': losingPatterns.map((k, v) => MapEntry(k, v.toJson())),
  };

  void loadFromJson(Map<String, dynamic> j) {
    try {
      regime = MarketRegime.values.firstWhere(
        (e) => e.name == j['regime'], orElse: () => MarketRegime.unknown);
      entryThreshold = (j['entryThreshold'] as num?)?.toDouble() ?? 55.0;
      totalTrades = j['totalTrades'] ?? 0;
      totalWins = j['totalWins'] ?? 0;
      totalLosses = j['totalLosses'] ?? 0;
      rollingPnL = (j['rollingPnL'] as num?)?.toDouble() ?? 0.0;
      if (j['perfs'] != null) {
        (j['perfs'] as Map).forEach((k, v) {
          perfs[k] = IndicatorPerf.fromJson(Map<String, dynamic>.from(v));
        });
      }
      if (j['losingPatterns'] != null) {
        (j['losingPatterns'] as Map).forEach((k, v) {
          losingPatterns[k] = LosingPattern.fromJson(Map<String, dynamic>.from(v));
        });
      }
    } catch (_) {}
  }

  // ============ Reset ============
  void reset() {
    regime = MarketRegime.unknown;
    entryThreshold = 55.0;
    totalTrades = 0;
    totalWins = 0;
    totalLosses = 0;
    rollingPnL = 0.0;
    perfs.clear();
    for (final id in _allIds) perfs[id] = IndicatorPerf(id: id);
    losingPatterns.clear();
  }
}
