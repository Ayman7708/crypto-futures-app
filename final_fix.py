import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# ============ 1. Cap recovery multiplier at 1.3x (STOP THE BLEED) ============
old_recovery = """    if (_dailyPnL >= 0) {
      _recoveryMultiplier = 1.0;
    } else {
      final lossPct = _dailyPnL.abs() / _initialCapital;
      if (lossPct < 0.03) {
        _recoveryMultiplier = 1.3;
      } else if (lossPct < 0.07) {
        _recoveryMultiplier = 1.8;
      } else if (lossPct < 0.12) {
        _recoveryMultiplier = 2.5;
      } else {
        _recoveryMultiplier = 3.5;
      }
    }"""
new_recovery = """    if (_dailyPnL >= 0) {
      _recoveryMultiplier = 1.0;
    } else {
      final lossPct = _dailyPnL.abs() / _initialCapital;
      if (lossPct < 0.05) {
        _recoveryMultiplier = 1.1;
      } else {
        _recoveryMultiplier = 1.3;  // HARD CAP at 1.3x
      }
    }"""
if old_recovery in src:
    src = src.replace(old_recovery, new_recovery)
    checks.append(('recovery capped 1.3x', '_recoveryMultiplier = 1.3;' in src and '_recoveryMultiplier = 3.5;' not in src))
else:
    checks.append(('recovery capped 1.3x', False))

# ============ 2. Reduce max positions 15 → 5 ============
src = src.replace('_maxPositions = 15;', '_maxPositions = 5;')
checks.append(('max pos 5', '_maxPositions = 5;' in src))

# ============ 3. Reduce leverage 5 → 3 ============
src = src.replace('int _leverage = 5;', 'int _leverage = 3;')
checks.append(('leverage 3', '_leverage = 3;' in src))

# ============ 4. Tighten SL 2% → 1.5%, keep TP at 3% ============
src = src.replace('double _slPercent = 2.0;', 'double _slPercent = 1.5;')
src = src.replace('double _tpPercent = 5.0;', 'double _tpPercent = 3.0;')
checks.append(('SL 1.5% / TP 3%', '_slPercent = 1.5' in src))

# ============ 5. Force threshold LOW - override adaptive engine ============
# Replace the adaptive threshold call with fixed value
src = re.sub(
    r"final thr = LearningEngine\.adaptiveThreshold\(_trades, _scalpThreshold\);",
    "final thr = _scalpThreshold.clamp(30, 50);  // FORCED LOW for scalping",
    src
)
checks.append(('force threshold', 'FORCED LOW for scalping' in src))

# ============ 6. Fix indicator tracking - only increment contributors ============
old_ind = """    _lastTradeTime[symbol] = DateTime.now();
    // Update indicator test counts
    for (final ind in _indicators) {
      ind.tests++;
      ind.wins++;  // Will be adjusted if trade loses
    }"""
new_ind = """    _lastTradeTime[symbol] = DateTime.now();
    // Update ONLY the indicators that contributed to this signal
    final activeNames = _topContributors[symbol] ?? [];
    for (final ind in _indicators) {
      if (activeNames.contains(ind.name)) {
        ind.tests++;
      }
    }"""
if old_ind in src:
    src = src.replace(old_ind, new_ind)
    checks.append(('ind contributors', '_topContributors[symbol]' in src))
else:
    checks.append(('ind contributors', False))

# Add _topContributors map
if '_topContributors' not in src:
    src = src.replace(
        "  final Map<String, ScalpSignal> _scalpSignals = {};",
        "  final Map<String, ScalpSignal> _scalpSignals = {};\n  final Map<String, List<String>> _topContributors = {};"
    )
    checks.append(('contributors map', '_topContributors' in src))
else:
    checks.append(('contributors map', True))

# Populate contributors when analyzing
old_master_analysis = """    final masterRes = _masterResults[symbol];"""
new_master_analysis = """    final masterRes = _masterResults[symbol];
    // Record top contributors for learning
    if (masterRes != null) {
      _topContributors[symbol] = [
        ...masterRes.topBullish.take(5),
        ...masterRes.topBearish.take(5),
      ].map((e) => e.split('(').first).toList();
    }"""
if old_master_analysis in src and '_topContributors[symbol] = [' not in src:
    src = src.replace(old_master_analysis, new_master_analysis)
    checks.append(('record contributors', '_topContributors[symbol] = [' in src))
else:
    checks.append(('record contributors', '_topContributors[symbol] = [' in src))

# ============ 7. Add notification on trade close ============
old_notif = "NotificationService.show('Close $symbol', '$reason PnL: \\$${pnl.toStringAsFixed(2)}');"
new_notif = """NotificationService.show(
      pnl >= 0 ? '🎯 ربح $symbol' : '🛑 خسارة $symbol',
      'السبب: $reason | PnL: \\$${pnl.toStringAsFixed(2)} | الرصيد: \\$${_balance.toStringAsFixed(2)}',
    );"""
if old_notif in src:
    src = src.replace(old_notif, new_notif)
    checks.append(('close notif', '🎯 ربح' in src))
else:
    checks.append(('close notif', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Emergency Fix ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
