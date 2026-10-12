with open('lib/master_signal.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Add imports
if "import 'indicators_v3.dart';" not in src:
    src = src.replace(
        "import 'indicators_v2.dart';",
        "import 'indicators_v2.dart';\nimport 'indicators_v3.dart';\nimport 'auto_filter.dart';"
    )
checks.append(('imports', "import 'indicators_v3.dart';" in src))

# 2) Add AutoFilter field to MasterSignal
old_field = "  final Map<String, int> wins = {};\n  final Map<String, int> losses = {};"
new_field = """  final Map<String, int> wins = {};
  final Map<String, int> losses = {};
  final AutoFilter filter = AutoFilter();"""
if old_field in src and 'final AutoFilter filter' not in src:
    src = src.replace(old_field, new_field)
    checks.append(('filter field', 'final AutoFilter filter' in src))
else:
    checks.append(('filter field', 'final AutoFilter filter' in src))

# 3) Add 15 new indicator names to _allNames
old_names_end = "    'Divergence', 'KDJ', 'RVI', 'Pivot', 'Elder Ray', 'Schaff', 'Coppock',\n  ];"
new_names_end = """    'Divergence', 'KDJ', 'RVI', 'Pivot', 'Elder Ray', 'Schaff', 'Coppock',
    // V3 - 15 more
    'Zigzag', 'Heikin-Ashi', 'Alligator', 'Fractals', 'Gator',
    'Accelerator', 'Bulls Power', 'Bears Power', 'Chaikin Osc',
    'BB %B', 'Choppiness', 'Klinger', 'Twiggs MF', 'Elder Impulse', 'SMI',
    'RVI Vigor', 'WaveTrend',
  ];"""
if old_names_end in src and "'Zigzag', 'Heikin-Ashi'" not in src:
    src = src.replace(old_names_end, new_names_end)
    checks.append(('new names', "'Zigzag', 'Heikin-Ashi'" in src))
else:
    checks.append(('new names', "'Zigzag', 'Heikin-Ashi'" in src))

# 4) Add votes for new indicators - find the last vote (Coppock) and add after it
old_last_vote = """    final coppock = IndicatorsV2.coppock(closes);
    if (coppock != null) {
      votes.add(SignalVote('Coppock', 'Reversal', coppock > 0 ? 60 : -60, weights['Coppock']!));
    }"""

new_last_vote = """    final coppock = IndicatorsV2.coppock(closes);
    if (coppock != null) {
      votes.add(SignalVote('Coppock', 'Reversal', coppock > 0 ? 60 : -60, weights['Coppock']!));
    }

    // ============ V3 INDICATORS ============
    final zz = IndicatorsV3.zigzag(closes, 5);
    if (zz != null && zz > 2) {
      votes.add(SignalVote('Zigzag', 'Reversal', 50, weights['Zigzag']!));
    }
    final haDir = IndicatorsV3.heikinAshi(closes, highs, lows, closes);
    votes.add(SignalVote('Heikin-Ashi', 'Trend', haDir == 'BULL' ? 60 : -60, weights['Heikin-Ashi']!));
    final (agJ, agT, agL) = IndicatorsV3.alligator(closes);
    if (agJ != null && agT != null && agL != null) {
      final v = agL > agT && agT > agJ ? 70 : (agL < agT && agT < agJ ? -70 : 0);
      votes.add(SignalVote('Alligator', 'Trend', v, weights['Alligator']!));
    }
    final fr = IndicatorsV3.fractals(highs, lows, 2);
    if (fr > 0) {
      votes.add(SignalVote('Fractals', 'Reversal', closes.last > closes[closes.length - 2] ? 50 : -50, weights['Fractals']!));
    }
    final gat = IndicatorsV3.gator(closes);
    if (gat != null) {
      votes.add(SignalVote('Gator', 'Trend', gat < 1 ? 40 : 0, weights['Gator']!));
    }
    final acc = IndicatorsV3.accelerator(highs, lows, closes);
    if (acc != null) {
      votes.add(SignalVote('Accelerator', 'Momentum', acc > 0 ? 60 : -60, weights['Accelerator']!));
    }
    final bp = IndicatorsV3.bullsPower(highs, closes, 13);
    if (bp != null) {
      votes.add(SignalVote('Bulls Power', 'Momentum', bp > 0 ? 60 : -60, weights['Bulls Power']!));
    }
    final brp = IndicatorsV3.bearsPower(lows, closes, 13);
    if (brp != null) {
      votes.add(SignalVote('Bears Power', 'Momentum', brp > 0 ? -60 : 60, weights['Bears Power']!));
    }
    final chk = IndicatorsV3.chaikinOscillator(highs, lows, closes, volumes, 3, 10);
    if (chk != null) {
      votes.add(SignalVote('Chaikin Osc', 'Volume', chk > 0 ? 60 : -60, weights['Chaikin Osc']!));
    }
    final bbB = IndicatorsV3.bollingerPercentB(closes, 20, 2);
    if (bbB != null) {
      final v = bbB < 0 ? 70 : (bbB > 1 ? -70 : ((bbB - 0.5) * 80).toInt());
      votes.add(SignalVote('BB %B', 'Volatility', v, weights['BB %B']!));
    }
    final chop = IndicatorsV3.choppiness(highs, lows, closes, 14);
    if (chop != null) {
      final v = chop < 38 ? 60 : (chop > 62 ? -30 : 0);
      votes.add(SignalVote('Choppiness', 'Volatility', v, weights['Choppiness']!));
    }
    final klg = IndicatorsV3.klinger(highs, lows, closes, volumes, 34, 55);
    if (klg != null) {
      votes.add(SignalVote('Klinger', 'Volume', klg > 0 ? 60 : -60, weights['Klinger']!));
    }
    final twg = IndicatorsV3.twiggsMoneyFlow(highs, lows, closes, volumes, 21);
    if (twg != null) {
      final v = twg > 50 ? 60 : (twg < 50 ? -30 : 0);
      votes.add(SignalVote('Twiggs MF', 'Volume', v, weights['Twiggs MF']!));
    }
    final ei = IndicatorsV3.elderImpulse(closes, highs, lows, 13);
    votes.add(SignalVote('Elder Impulse', 'Trend', ei == 'GREEN' ? 70 : (ei == 'RED' ? -70 : 0), weights['Elder Impulse']!));
    final smi = IndicatorsV3.smi(highs, lows, closes, 14);
    if (smi != null) {
      final v = smi < -40 ? 70 : (smi > 40 ? -70 : smi.clamp(-60, 60).toInt());
      votes.add(SignalVote('SMI', 'Momentum', v, weights['SMI']!));
    }
    final rviV = IndicatorsV3.rviVigor(closes, highs, lows, closes, 10);
    if (rviV != null) {
      votes.add(SignalVote('RVI Vigor', 'Momentum', (rviV * 200).clamp(-100, 100).toInt(), weights['RVI Vigor']!));
    }
    final (wt, _) = IndicatorsV3.waveTrend(highs, lows, closes, 10);
    if (wt != null) {
      final v = wt < -60 ? 70 : (wt > 60 ? -70 : wt.clamp(-60, 60).toInt());
      votes.add(SignalVote('WaveTrend', 'Momentum', v, weights['WaveTrend']!));
    }"""

if old_last_vote in src and 'V3 INDICATORS' not in src:
    src = src.replace(old_last_vote, new_last_vote)
    checks.append(('v3 votes', 'V3 INDICATORS' in src))
else:
    checks.append(('v3 votes', 'V3 INDICATORS' in src))

# 5) Filter out deleted indicators before counting
old_count = "    // ============ COMPUTE WEIGHTED SCORES ============\n    double bullSum = 0, bullTotalW = 0;"
new_count = """    // ============ FILTER OUT DELETED INDICATORS ============
    final activeVotes = votes.where((v) => filter.isActive(v.name)).toList();

    // Register votes in filter
    for (final v in activeVotes) {
      filter.registerVote(v.name);
    }

    // ============ COMPUTE WEIGHTED SCORES ============
    double bullSum = 0, bullTotalW = 0;"""
if old_count in src and 'FILTER OUT DELETED' not in src:
    src = src.replace(old_count, new_count)
    checks.append(('filter votes', 'FILTER OUT DELETED' in src))
else:
    checks.append(('filter votes', 'FILTER OUT DELETED' in src))

# 6) Use activeVotes for computation
src = src.replace(
    "    for (final v in votes) {\n      if (v.vote > 0) {",
    "    for (final v in activeVotes) {\n      if (v.vote > 0) {"
)
src = src.replace(
    "    int bullCount = votes.where((v) => v.vote > 30).length;\n    int bearCount = votes.where((v) => v.vote < -30).length;",
    "    int bullCount = activeVotes.where((v) => v.vote > 30).length;\n    int bearCount = activeVotes.where((v) => v.vote < -30).length;"
)
checks.append(('use active', 'activeVotes.where((v) => v.vote > 30)' in src))

# 7) Update updateFromTrade to feed auto-filter
old_update = """  void updateFromTrade(List<SignalVote> votes, bool wasWin) {
    for (final v in votes) {
      if (wasWin) {
        wins[v.name] = (wins[v.name] ?? 0) + 1;
        weights[v.name] = min(3.0, (weights[v.name] ?? 1.0) * 1.08);
      } else {
        losses[v.name] = (losses[v.name] ?? 0) + 1;
        weights[v.name] = max(0.2, (weights[v.name] ?? 1.0) * 0.93);
      }
    }
  }"""

new_update = """  void updateFromTrade(List<SignalVote> votes, bool wasWin) {
    final names = <String>[];
    for (final v in votes) {
      names.add(v.name);
      if (wasWin) {
        wins[v.name] = (wins[v.name] ?? 0) + 1;
        weights[v.name] = min(3.0, (weights[v.name] ?? 1.0) * 1.08);
      } else {
        losses[v.name] = (losses[v.name] ?? 0) + 1;
        weights[v.name] = max(0.2, (weights[v.name] ?? 1.0) * 0.93);
      }
    }
    // Feed auto-filter
    filter.updateFromTrade(names, wasWin);
  }"""
if old_update in src and 'filter.updateFromTrade' not in src:
    src = src.replace(old_update, new_update)
    checks.append(('update filter', 'filter.updateFromTrade' in src))
else:
    checks.append(('update filter', 'filter.updateFromTrade' in src))

# 8) Save/load filter
old_save = "  Map<String, dynamic> toJson() => {\n    'weights': weights, 'wins': wins, 'losses': losses,\n  };"
new_save = "  Map<String, dynamic> toJson() => {\n    'weights': weights, 'wins': wins, 'losses': losses,\n    'filter': filter.toJson(),\n  };"
if old_save in src and "'filter': filter.toJson()" not in src:
    src = src.replace(old_save, new_save)
    checks.append(('save filter', "'filter': filter.toJson()" in src))
else:
    checks.append(('save filter', "'filter': filter.toJson()" in src))

old_load = """      if (j['losses'] != null) {
        (j['losses'] as Map).forEach((k, v) {
          losses[k.toString()] = v as int;
        });
      }
    } catch (_) {}"""

new_load = """      if (j['losses'] != null) {
        (j['losses'] as Map).forEach((k, v) {
          losses[k.toString()] = v as int;
        });
      }
      if (j['filter'] != null) {
        filter.loadFromJson(Map<String, dynamic>.from(j['filter']));
      }
    } catch (_) {}"""
if old_load in src and "j['filter']" not in src:
    src = src.replace(old_load, new_load)
    checks.append(('load filter', "j['filter']" in src))
else:
    checks.append(('load filter', "j['filter']" in src))

with open('lib/master_signal.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Master Upgrade ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
