with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# === 1. Reduce cooldown from 600 → 30 seconds ===
if '_cooldownSeconds = 600' in src:
    src = src.replace('static const int _cooldownSeconds = 600;',
                      'static const int _cooldownSeconds = 30;')
    checks.append(('cooldown 30s', '_cooldownSeconds = 30' in src))
elif '_cooldownSeconds = 60' in src:
    src = src.replace('static const int _cooldownSeconds = 60;',
                      'static const int _cooldownSeconds = 30;')
    checks.append(('cooldown 30s', '_cooldownSeconds = 30' in src))
else:
    # find and replace
    import re
    m = re.search(r'static const int _cooldownSeconds = \d+;', src)
    if m:
        src = src.replace(m.group(0), 'static const int _cooldownSeconds = 30;')
        checks.append(('cooldown 30s', True))
    else:
        checks.append(('cooldown 30s', False))

# === 2. Reduce profit lockout from 15 min → 1 min ===
src = src.replace('if (mins < 15) return;', 'if (mins < 1) return;')
checks.append(('lockout 1min', 'if (mins < 1) return;' in src))

# === 3. Increase max positions from 5 → 15 ===
src = src.replace('final int _maxPositions = 5;', 'final int _maxPositions = 15;')
checks.append(('max pos 15', '_maxPositions = 15' in src))

# === 4. Reduce scalp threshold from 65 → 30 ===
src = src.replace('int _scalpThreshold = 65;', 'int _scalpThreshold = 30;')
checks.append(('scalp thr 30', '_scalpThreshold = 30' in src))

# === 5. Reduce LONG score requirement from 60 → 35 ===
src = src.replace(
    "if (signal.direction == 'LONG' && signal.score >= 60 && learnedOK && _positions.length < _maxPositions)",
    "if (signal.direction == 'LONG' && signal.score >= 35 && _positions.length < _maxPositions)"
)
src = src.replace(
    "if (signal.direction == 'LONG' && signal.score >= 60 && learnedOK && canTakeMore && isTopCoin)",
    "if (signal.direction == 'LONG' && signal.score >= 35 && canTakeMore)"
)
checks.append(('LONG 35', 'signal.score >= 35' in src))

# === 6. Reduce scalp entry score from 55 → 30 ===
src = src.replace(
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 55 && _positions.length < _maxPositions && _canTradeSymbol(symbol))",
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 30 && canTakeMore)"
)
src = src.replace(
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 55 && canTakeMore)",
    "if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 30 && canTakeMore)"
)
checks.append(('scalp 30', 'signal.score >= 30' in src))

# === 7. Reduce SHORT threshold too ===
src = src.replace(
    "final shortOK = shortScore >= effectiveThresholdShort &&\n                    shortMult > 0.5 &&\n                    canTakeMore && isTopCoin &&",
    "final shortOK = shortScore >= 40 &&\n                    shortMult > 0.5 &&\n                    canTakeMore &&"
)
checks.append(('short 40', 'shortScore >= 40' in src))

# === 8. Make master signal blend more permissive (50/50) ===
src = src.replace('(signal.score * 0.3 + masterBull * 0.7)', '(signal.score * 0.5 + masterBull * 0.5)')
src = src.replace('(signal.score * 0.3 + masterBear * 0.7)', '(signal.score * 0.5 + masterBear * 0.5)')
checks.append(('blend 50/50', 'signal.score * 0.5' in src))

# === 9. Master signal lower thresholds for LONG/SHORT ===
src = src.replace(
    "if (masterBull > masterBear) {",
    "if (masterBull >= masterBear - 10) {"
)
checks.append(('master loose', 'masterBull >= masterBear - 10' in src))

# === 10. Remove the effectiveThreshold calculation strictness ===
src = src.replace(
    "final baseThreshold = (_scalpThreshold + thresholdAdj).clamp(40, 85);",
    "final baseThreshold = (_scalpThreshold + thresholdAdj).clamp(25, 70);"
)
checks.append(('base threshold 25', '.clamp(25, 70)' in src))

# === 11. Force open a minimum number of trades to fill slots ===
# Add aggressive scalping at the top of _process
old_section = "    if (pos != null) {\n      if (ss < sl && rsi > _rsiSell) _closePosition(symbol, price, 'SELL');"
# (This may not exist anymore, skip if not found)

# === 12. Ensure indicators update on every open (was already there)
# Verify it still exists
if 'ind.tests++' in src:
    checks.append(('ind.tests exists', True))
else:
    checks.append(('ind.tests exists', False))

# === 13. Force scalp mode active ===
src = src.replace('bool _scalpEnabled = true;', 'bool _scalpEnabled = true;')
# Make sure it's true
if 'bool _scalpEnabled = false;' in src:
    src = src.replace('bool _scalpEnabled = false;', 'bool _scalpEnabled = true;')

# === 14. Fast loop - ensure 5 seconds ===
src = src.replace('const int LOOP_SECONDS = 10;', 'const int LOOP_SECONDS = 5;')
checks.append(('loop 5s', 'LOOP_SECONDS = 5' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== BEAST MODE Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('==========================')
