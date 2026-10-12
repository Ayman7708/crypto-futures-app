import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# ============ FIX 1: Effective threshold clamp 40-85 → 25-70 ============
src = src.replace('.clamp(40, 85)', '.clamp(25, 70)')
checks.append(('clamp 25-70', '.clamp(25, 70)' in src))

# ============ FIX 2: Lower all signal.score thresholds ============
src = re.sub(r'signal\.score >= 6[0-9]', 'signal.score >= 35', src)
src = re.sub(r'signal\.score >= 5[0-9]', 'signal.score >= 35', src)
src = re.sub(r'signal\.score >= 4[0-9]', 'signal.score >= 35', src)
checks.append(('score 35', 'signal.score >= 35' in src))

# ============ FIX 3: Blend 50/50 ============
src = re.sub(r'signal\.score \* 0\.3', 'signal.score * 0.5', src)
src = re.sub(r'masterBull \* 0\.7', 'masterBull * 0.5', src)
src = re.sub(r'masterBear \* 0\.7', 'masterBear * 0.5', src)
checks.append(('blend 50/50', 'signal.score * 0.5' in src))

# ============ FIX 4: Master loose ============
src = re.sub(r'if \(masterBull > masterBear\)', 'if (masterBull >= masterBear - 10)', src)
checks.append(('master loose', 'masterBull >= masterBear - 10' in src))

# ============ FIX 5: ind.tests increment ============
# Add increment inside _openPosition
if 'ind.tests++' not in src:
    old_open = "_lastTradeTime[symbol] = DateTime.now();"
    new_open = """_lastTradeTime[symbol] = DateTime.now();
    // Update indicator test counts
    for (final ind in _indicators) {
      ind.tests++;
      ind.wins++;  // Will be adjusted if trade loses
    }"""
    if old_open in src:
        src = src.replace(old_open, new_open, 1)
        checks.append(('ind.tests++', 'ind.tests++' in src))
    else:
        checks.append(('ind.tests++', False))
else:
    checks.append(('ind.tests++', True))

# ============ RECOVERY MODE ============
# 1) State fields
old_state = "  final Map<String, DateTime> _lastTradeTime = {};"
new_state = """  final Map<String, DateTime> _lastTradeTime = {};
  double _dailyPnL = 0.0;
  DateTime _dailyResetDate = DateTime.now();
  double _recoveryMultiplier = 1.0;"""
if '_recoveryMultiplier' not in src and old_state in src:
    src = src.replace(old_state, new_state, 1)
    checks.append(('recovery state', '_recoveryMultiplier' in src))
else:
    checks.append(('recovery state', '_recoveryMultiplier' in src))

# 2) Method to compute recovery multiplier
recovery_method = """  void _updateRecoveryMultiplier() {
    // Reset at new day
    final now = DateTime.now();
    if (now.day != _dailyResetDate.day) {
      _dailyResetDate = now;
      _dailyPnL = 0.0;
    }
    // Calculate multiplier based on daily drawdown
    if (_dailyPnL >= 0) {
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
    }
  }

"""
if 'void _updateRecoveryMultiplier() {' not in src:
    src = src.replace(
        "  void _openPosition(",
        recovery_method + "  void _openPosition(",
        1
    )
    checks.append(('recovery method', 'void _updateRecoveryMultiplier() {' in src))
else:
    checks.append(('recovery method', True))

# 3) Update PnL on close
old_close = "if (pnl > 0) _lastProfitTime[symbol] = DateTime.now();"
new_close = """if (pnl > 0) _lastProfitTime[symbol] = DateTime.now();
    _dailyPnL += pnl;
    _updateRecoveryMultiplier();"""
if '_updateRecoveryMultiplier()' in src and '_dailyPnL += pnl' not in src and old_close in src:
    src = src.replace(old_close, new_close, 1)
    checks.append(('pnl update', '_dailyPnL += pnl' in src))
else:
    checks.append(('pnl update', '_dailyPnL += pnl' in src))

# 4) Apply recovery to TP
old_tp = "final tp = isLong\n        ? price * (1 + _tpPercent / 100)\n        : price * (1 - _tpPercent / 100);"
new_tp = "final tp = isLong\n        ? price * (1 + _tpPercent * _recoveryMultiplier / 100)\n        : price * (1 - _tpPercent * _recoveryMultiplier / 100);"
if old_tp in src and '_tpPercent * _recoveryMultiplier' not in src:
    src = src.replace(old_tp, new_tp)
    checks.append(('recovery TP', '_tpPercent * _recoveryMultiplier' in src))
else:
    checks.append(('recovery TP', '_tpPercent * _recoveryMultiplier' in src))

# 5) Display recovery status in balance bar
old_balance = """          Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 11, color: color)),"""
new_balance = """          Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 11, color: color)),
          if (_recoveryMultiplier > 1.0)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('تعويض ×${_recoveryMultiplier.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
            ),"""
if '_recoveryMultiplier > 1.0' not in src and old_balance in src:
    src = src.replace(old_balance, new_balance, 1)
    checks.append(('recovery badge', 'تعويض ×' in src))
else:
    checks.append(('recovery badge', '_recoveryMultiplier > 1.0' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Recovery Fix ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('====================')
