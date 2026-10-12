with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Find and replace the SL/TP management block in _process
old_management = """    if (pos != null) {
      // break-even: if profit reaches half of TP%, move SL to entry
      final profitPct = pos.isLong
          ? (price - pos.entry) / pos.entry * 100
          : (pos.entry - price) / pos.entry * 100;
      if (profitPct >= _tpPercent * 0.5) {
        final newSL = pos.entry;
        final better = pos.isLong ? newSL > pos.stopLoss : newSL < pos.stopLoss;
        if (better) {
          _positions[symbol] = Position(
            symbol: symbol, entry: pos.entry, size: pos.size, margin: pos.margin,
            stopLoss: newSL, takeProfit: pos.takeProfit, leverage: pos.leverage,
            isScalp: pos.isScalp,
          );
        }
      }
      // trailing stop: after +1%, trail by 0.5%
      if (profitPct >= 1.0) {
        final trailSL = pos.isLong
            ? price * (1 - 0.5 / 100)
            : price * (1 + 0.5 / 100);
        final cur = _positions[symbol]!;
        final trailBetter = pos.isLong ? trailSL > cur.stopLoss : trailSL < cur.stopLoss;
        if (trailBetter) {
          _positions[symbol] = Position(
            symbol: symbol, entry: cur.entry, size: cur.size, margin: cur.margin,
            stopLoss: trailSL, takeProfit: cur.takeProfit, leverage: cur.leverage,
            isScalp: cur.isScalp,
          );
        }
      }
      final slHit = pos.isLong ? price <= pos.stopLoss : price >= pos.stopLoss;
      final tpHit = pos.isLong ? price >= pos.takeProfit : price <= pos.takeProfit;
      final liqHit = pos.isLong ? price <= pos.liquidationPrice : price >= pos.liquidationPrice;
      if (slHit) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (tpHit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      if (liqHit) { _closePosition(symbol, price, 'LIQUIDATED'); return; }
    }"""

new_management = """    if (pos != null) {
      final profitPct = pos.isLong
          ? (price - pos.entry) / pos.entry * 100
          : (pos.entry - price) / pos.entry * 100;

      // === 1. Break-even عند +1.5% ===
      if (profitPct >= 1.5) {
        final newSL = pos.entry;
        final better = pos.isLong ? newSL > pos.stopLoss : newSL < pos.stopLoss;
        if (better) {
          _positions[symbol] = Position(
            symbol: symbol, entry: pos.entry, size: pos.size, margin: pos.margin,
            stopLoss: newSL, takeProfit: pos.takeProfit, leverage: pos.leverage,
            isScalp: pos.isScalp, isLong: pos.isLong,
          );
        }
      }

      // === 2. Trailing Stop متدرج (Dynamic) ===
      if (profitPct >= 2.0) {
        double trailDistance;
        if (profitPct < 4.0) {
          trailDistance = 1.5;  // ربح 2-4% → اتبع بمسافة 1.5%
        } else if (profitPct < 6.0) {
          trailDistance = 1.0;  // ربح 4-6% → اتبع بمسافة 1.0%
        } else {
          trailDistance = 0.7;  // ربح 6%+ → اتبع بمسافة 0.7%
        }
        final trailSL = pos.isLong
            ? price * (1 - trailDistance / 100)
            : price * (1 + trailDistance / 100);
        final cur = _positions[symbol]!;
        final trailBetter = pos.isLong ? trailSL > cur.stopLoss : trailSL < cur.stopLoss;
        if (trailBetter) {
          _positions[symbol] = Position(
            symbol: symbol, entry: cur.entry, size: cur.size, margin: cur.margin,
            stopLoss: trailSL, takeProfit: cur.takeProfit, leverage: cur.leverage,
            isScalp: cur.isScalp, isLong: cur.isLong,
          );
        }
      }

      // === 3. Dynamic Take Profit ===
      // TP يرتفع كل ما زاد الربح (للمراكز الرابحة فقط)
      if (profitPct >= 2.0) {
        final curPos = _positions[symbol]!;
        double newTP;
        if (profitPct < 4.0) {
          newTP = pos.entry * (pos.isLong ? 1.05 : 0.95);  // TP عند +5%
        } else if (profitPct < 6.0) {
          newTP = pos.entry * (pos.isLong ? 1.08 : 0.92);  // TP عند +8%
        } else {
          newTP = pos.entry * (pos.isLong ? 1.12 : 0.88);  // TP عند +12%
        }
        final tpBetter = pos.isLong ? newTP > curPos.takeProfit : newTP < curPos.takeProfit;
        if (tpBetter) {
          _positions[symbol] = Position(
            symbol: symbol, entry: curPos.entry, size: curPos.size, margin: curPos.margin,
            stopLoss: curPos.stopLoss, takeProfit: newTP, leverage: curPos.leverage,
            isScalp: curPos.isScalp, isLong: curPos.isLong,
          );
        }
      }

      // === 4. فحوصات الإغلاق ===
      final updatedPos = _positions[symbol]!;
      final slHit = updatedPos.isLong ? price <= updatedPos.stopLoss : price >= updatedPos.stopLoss;
      final tpHit = updatedPos.isLong ? price >= updatedPos.takeProfit : price <= updatedPos.takeProfit;
      final liqHit = updatedPos.isLong ? price <= updatedPos.liquidationPrice : price >= updatedPos.liquidationPrice;
      if (slHit) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (tpHit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      if (liqHit) { _closePosition(symbol, price, 'LIQUIDATED'); return; }
    }"""

if old_management in src:
    src = src.replace(old_management, new_management)
    checks.append(('smart trail', 'Trailing Stop متدرج' in src and 'Dynamic Take Profit' in src))
else:
    checks.append(('smart trail', False))

# Change default SL/TP
src = src.replace("double _slPercent = 1.5;", "double _slPercent = 2.0;")
src = src.replace("double _tpPercent = 3.0;", "double _tpPercent = 5.0;")
checks.append(('SL 2%, TP 5%', '_slPercent = 2.0' in src and '_tpPercent = 5.0' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Smart Trail Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('==========================')
