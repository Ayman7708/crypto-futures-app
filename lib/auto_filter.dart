class IndicatorStats {
  String name;
  int wins;
  int losses;
  int votes;
  double weight;
  bool active;
  bool deleted;

  IndicatorStats({
    required this.name,
    this.wins = 0, this.losses = 0, this.votes = 0,
    this.weight = 1.0, this.active = true, this.deleted = false,
  });

  double get winRate => (wins + losses) == 0 ? 0.5 : wins / (wins + losses);
  double get confidence => (wins + losses) < 10 ? 0.3 : ((wins + losses) / 100).clamp(0.3, 1.0);

  Map<String, dynamic> toJson() => {
    'name': name, 'wins': wins, 'losses': losses, 'votes': votes,
    'weight': weight, 'active': active, 'deleted': deleted,
  };

  factory IndicatorStats.fromJson(Map<String, dynamic> j) => IndicatorStats(
    name: j['name'], wins: j['wins'] ?? 0, losses: j['losses'] ?? 0,
    votes: j['votes'] ?? 0, weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
    active: j['active'] ?? true, deleted: j['deleted'] ?? false,
  );
}

class AutoFilter {
  final Map<String, IndicatorStats> stats = {};

  // Criteria
  static const int minSamples = 15;       // Minimum samples before judging
  static const double deleteThreshold = 0.35;  // Win rate < 35% → delete
  static const double boostThreshold = 0.60;   // Win rate > 60% → boost
  static const double maxWeight = 3.0;
  static const double minWeight = 0.2;

  IndicatorStats getOrCreate(String name) {
    stats.putIfAbsent(name, () => IndicatorStats(name: name));
    return stats[name]!;
  }

  // Register a vote
  void registerVote(String name) {
    getOrCreate(name).votes++;
  }

  // Update after trade closes
  void updateFromTrade(List<String> indicators, bool wasWin) {
    for (final name in indicators) {
      final s = getOrCreate(name);
      if (wasWin) {
        s.wins++;
        s.weight = (s.weight * 1.08).clamp(minWeight, maxWeight).toDouble();
      } else {
        s.losses++;
        s.weight = (s.weight * 0.93).clamp(minWeight, maxWeight).toDouble();
      }
      // Auto-delete if bad
      final total = s.wins + s.losses;
      if (total >= minSamples && s.winRate < deleteThreshold) {
        s.active = false;
        s.deleted = true;
      }
      // Reactivate if good (in case it was deleted)
      if (total >= minSamples && s.winRate > boostThreshold && s.deleted) {
        s.active = true;
        s.deleted = false;
      }
    }
  }

  List<IndicatorStats> getActive() {
    return stats.values.where((s) => s.active && !s.deleted).toList()
      ..sort((a, b) => b.winRate.compareTo(a.winRate));
  }

  List<IndicatorStats> getGraveyard() {
    return stats.values.where((s) => s.deleted).toList()
      ..sort((a, b) => a.winRate.compareTo(b.winRate));
  }

  List<IndicatorStats> getTopPerformers({int n = 10}) {
    return stats.values.where((s) => s.wins + s.losses >= 5).toList()
      ..sort((a, b) => b.winRate.compareTo(a.winRate));
  }

  Map<String, double> getActiveWeights() {
    final m = <String, double>{};
    for (final s in stats.values) {
      if (s.active && !s.deleted) m[s.name] = s.weight;
    }
    return m;
  }

  bool isActive(String name) {
    final s = stats[name];
    return s == null || s.active;
  }

  Map<String, dynamic> toJson() => {
    'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
  };

  void loadFromJson(Map<String, dynamic> j) {
    try {
      if (j['stats'] != null) {
        stats.clear();
        (j['stats'] as Map).forEach((k, v) {
          stats[k.toString()] = IndicatorStats.fromJson(Map<String, dynamic>.from(v));
        });
      }
    } catch (_) {}
  }
}
