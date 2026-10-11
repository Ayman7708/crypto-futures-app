with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Import market_regime
if "import 'market_regime.dart';" not in src:
    src = src.replace(
        "import 'strategies.dart';",
        "import 'strategies.dart';\nimport 'market_regime.dart';"
    )
checks.append(('import', "import 'market_regime.dart';" in src))

# 2) REMOVE protection layers (undo)
# 2a) Remove _canOpen() call from _openPosition
src = src.replace("    if (!_canOpen()) return;\n    final size = ", "    final size = ")
checks.append(('remove canOpen call', 'if (!_canOpen()) return;' not in src))

# 2b) Remove protection state vars (keep _master)
old_state = """  final MasterEngine _master = MasterEngine();
  double _dailyStartBalance = 0;
  DateTime _dailyStartDate = DateTime.now();
  int _dailyLossLimitPct = 10;
  bool _globalTrendFilter = true;
  int _maxConcurrentLosses = 3;"""
new_state = """  final MasterEngine _master = MasterEngine();
  MarketAnalysis? _marketAnalysis;"""
if old_state in src:
    src = src.replace(old_state, new_state)
    checks.append(('remove protection vars', '_dailyStartBalance' not in src))
else:
    checks.append(('remove protection vars', False))

# 2c) Remove daily reset code
old_reset = """        // Reset daily reference if new day
        final now = DateTime.now();
        if (_dailyStartDate.year != now.year || _dailyStartDate.month != now.month || _dailyStartDate.day != now.day) {
          _dailyStartDate = now;
          _dailyStartBalance = _balance;
        } else if (_dailyStartBalance == 0) {
          _dailyStartBalance = _balance;
        }
        _loaded = true;"""
new_reset = "        _loaded = true;"
if old_reset in src:
    src = src.replace(old_reset, new_reset)
    checks.append(('remove daily reset', '_dailyStartDate' not in src))
else:
    checks.append(('remove daily reset', False))

# 2d) Remove _canOpen method
import re
can_open_pattern = re.compile(r"  bool _canOpen\(\) \{.*?\n  \}\n\n", re.DOTALL)
src, n = can_open_pattern.subn("", src, count=1)
checks.append(('remove canOpen method', 'bool _canOpen()' not in src))

# 3) Update market analysis on each tick
old_tick = """      // Update market regime from BTC (reference)
      if (_priceHistory['BTCUSDT'] != null && _priceHistory['BTCUSDT']!.length >= 30) {
        _learner.detectRegime(
          closes: _priceHistory['BTCUSDT']!,
          highs: _highHistory['BTCUSDT']!,
          lows: _lowHistory['BTCUSDT']!,
        );
      }
    });"""
new_tick = """      // Market regime analysis (BTC + alts)
      final btcHist = _priceHistory['BTCUSDT'];
      if (btcHist != null && btcHist.length >= 50) {
        _learner.detectRegime(
          closes: btcHist,
          highs: _highHistory['BTCUSDT']!,
          lows: _lowHistory['BTCUSDT']!,
        );
        // Build alt map excluding BTC
        final altMap = <String, List<double>>{};
        for (final sym in SYMBOLS) {
          if (sym == 'BTCUSDT') continue;
          final h = _priceHistory[sym];
          if (h != null && h.length >= 50) altMap[sym] = h;
        }
        _marketAnalysis = MarketRegimeAnalyzer.analyze(
          btcCloses: btcHist, altCloses: altMap,
        );
      }
    });"""
if old_tick in src:
    src = src.replace(old_tick, new_tick)
    checks.append(('market tick', '_marketAnalysis = MarketRegimeAnalyzer' in src))
else:
    checks.append(('market tick', False))

# 4) Update _process to use regime bias for LONG/SHORT
old_open_section = """    if (_longBias) {
      if (signal.direction == 'LONG' && signal.score >= 60 && learnedOK && _positions.length < _maxPositions) {
        _openPosition(symbol, price, isScalp: signal.score >= 70);
        for (final ind in _indicators) {
          ind.tests++;
          if (signal.score >= 70) ind.wins++;
        }
      }
    } else {
      if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= 55 && _positions.length < _maxPositions && _canTradeSymbol(symbol)) {
        _openPosition(symbol, price, isScalp: true);
        return;
      }
      if (ss > sl && rsi < _rsiBuy) _openPosition(symbol, price, isScalp: false);
    }
    LearningEngine.updateWeights(_indicators, _trades);"""

new_open_section = """    // === Market-adaptive direction selection ===
    Regime regime = Regime.neutral;
    double longMult = 1.0, shortMult = 1.0;
    int thresholdAdj = 0;
    if (_marketAnalysis != null) {
      regime = _marketAnalysis!.regime;
      final (lm, sm, adj) = MarketRegimeAnalyzer.tradingBias(
        regime, _marketAnalysis!.altseasonScore,
      );
      longMult = lm;
      shortMult = sm;
      thresholdAdj = adj;
    }

    final baseThreshold = (_scalpThreshold + thresholdAdj).clamp(40, 85);
    final effectiveThreshold = _longBias
        ? (baseThreshold / longMult).clamp(40, 85).toInt()
        : (baseThreshold / shortMult).clamp(40, 85).toInt();
    final effectiveThresholdShort = (baseThreshold / shortMult).clamp(40, 85).toInt();

    final canTakeMore = _positions.length < _maxPositions && _canTradeSymbol(symbol);

    // Try LONG first (if bias allows)
    final longOK = signal.score >= effectiveThreshold &&
                   longMult > 0.5 &&
                   learnedOK && canTakeMore;
    if (signal.direction == 'LONG' && longOK) {
      _openPosition(symbol, price, isScalp: signal.score >= 70, isLong: true);
      LearningEngine.updateWeights(_indicators, _trades);
      return;
    }

    // Try SHORT (if regime favors bearish or neutral)
    final shortScore = signal.score; // Reuse same score logic in reverse
    final shortOK = shortScore >= effectiveThresholdShort &&
                    shortMult > 0.5 &&
                    canTakeMore &&
                    (regime == Regime.bearStrong ||
                     regime == Regime.bearWeak ||
                     (regime == Regime.neutral && shortMult >= 1.0));
    if (shortOK && signal.direction != 'LONG') {
      _openPosition(symbol, price, isScalp: shortScore >= 70, isLong: false);
      LearningEngine.updateWeights(_indicators, _trades);
      return;
    }

    LearningEngine.updateWeights(_indicators, _trades);"""

if old_open_section in src:
    src = src.replace(old_open_section, new_open_section)
    checks.append(('regime entry', 'MarketRegimeAnalyzer.tradingBias' in src))
else:
    checks.append(('regime entry', False))

# 5) Update _openPosition signature to accept isLong
old_open = "  void _openPosition(String symbol, double price, {required bool isScalp}) {"
new_open = "  void _openPosition(String symbol, double price, {required bool isScalp, bool isLong = true}) {"
if old_open in src:
    src = src.replace(old_open, new_open)
    checks.append(('open signature', 'isLong = true' in src))
else:
    checks.append(('open signature', False))

# 6) Update SL/TP calc for SHORT
old_sltp = """    final size = (_marginPerTrade * _leverage) / price;
    final sl = price * (1 - _slPercent / 100);
    final tp = price * (1 + _tpPercent / 100);"""
new_sltp = """    final size = (_marginPerTrade * _leverage) / price;
    final sl = isLong
        ? price * (1 - _slPercent / 100)
        : price * (1 + _slPercent / 100);
    final tp = isLong
        ? price * (1 + _tpPercent / 100)
        : price * (1 - _tpPercent / 100);"""
if old_sltp in src:
    src = src.replace(old_sltp, new_sltp)
    checks.append(('SL/TP short', 'isLong\n        ? price * (1 - _slPercent' in src))
else:
    checks.append(('SL/TP short', False))

# 7) Add isLong to Position creation
old_pos_create = """    _positions[symbol] = Position(
      symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
      stopLoss: sl, takeProfit: tp, leverage: _leverage, isScalp: isScalp,
    );
    _lastTradeTime[symbol] = DateTime.now();"""
new_pos_create = """    _positions[symbol] = Position(
      symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
      stopLoss: sl, takeProfit: tp, leverage: _leverage, isScalp: isScalp,
      isLong: isLong,
    );
    _lastTradeTime[symbol] = DateTime.now();"""
if old_pos_create in src:
    src = src.replace(old_pos_create, new_pos_create)
    checks.append(('pos create', 'isLong: isLong,' in src))
else:
    checks.append(('pos create', False))

# 8) Update SL/TP check in _process for both directions
old_check = """      if (price <= pos.stopLoss) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (price >= pos.takeProfit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      final liqPrice = pos.entry * (1 - 1 / pos.leverage);
      if (price <= liqPrice) { _closePosition(symbol, price, 'LIQUIDATED'); return; }"""
new_check = """      final slHit = pos.isLong ? price <= pos.stopLoss : price >= pos.stopLoss;
      final tpHit = pos.isLong ? price >= pos.takeProfit : price <= pos.takeProfit;
      final liqHit = pos.isLong ? price <= pos.liquidationPrice : price >= pos.liquidationPrice;
      if (slHit) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (tpHit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      if (liqHit) { _closePosition(symbol, price, 'LIQUIDATED'); return; }"""
if old_check in src:
    src = src.replace(old_check, new_check)
    checks.append(('SL/TP check', 'pos.isLong ? price <= pos.stopLoss' in src))
else:
    checks.append(('SL/TP check', False))

# 9) Update break-even/trailing for SHORT
old_be = """      final profitPct = (price - pos.entry) / pos.entry * 100;
      if (profitPct >= _tpPercent * 0.5) {
        final newSL = pos.entry;
        if (newSL > pos.stopLoss) {"""
new_be = """      final profitPct = pos.isLong
          ? (price - pos.entry) / pos.entry * 100
          : (pos.entry - price) / pos.entry * 100;
      if (profitPct >= _tpPercent * 0.5) {
        final newSL = pos.entry;
        final better = pos.isLong ? newSL > pos.stopLoss : newSL < pos.stopLoss;
        if (better) {"""
if old_be in src:
    src = src.replace(old_be, new_be)
    checks.append(('break-even short', 'pos.isLong\n          ? (price - pos.entry)' in src))
else:
    checks.append(('break-even short', False))

# 10) Update trailing for SHORT
old_trail = """      if (profitPct >= 1.0) {
        final trailSL = price * (1 - 0.5 / 100);
        final cur = _positions[symbol]!;
        if (trailSL > cur.stopLoss) {"""
new_trail = """      if (profitPct >= 1.0) {
        final trailSL = pos.isLong
            ? price * (1 - 0.5 / 100)
            : price * (1 + 0.5 / 100);
        final cur = _positions[symbol]!;
        final trailBetter = pos.isLong ? trailSL > cur.stopLoss : trailSL < cur.stopLoss;
        if (trailBetter) {"""
if old_trail in src:
    src = src.replace(old_trail, new_trail)
    checks.append(('trailing short', 'pos.isLong\n            ? price * (1 - 0.5' in src))
else:
    checks.append(('trailing short', False))

# 11) Add market analysis card in learning section
old_card_end = """        ..._master.strategies.map((s) {
          final w = _master.weights[s.name] ?? 1.0;
          final ww = _master.wins[s.name] ?? 0;
          final ll = _master.losses[s.name] ?? 0;
          return _indRow(s.name, 'W:${w.toStringAsFixed(2)} | ${ww}W/${ll}L');
        }),"""
new_card_end = """        ..._master.strategies.map((s) {
          final w = _master.weights[s.name] ?? 1.0;
          final ww = _master.wins[s.name] ?? 0;
          final ll = _master.losses[s.name] ?? 0;
          return _indRow(s.name, 'W:${w.toStringAsFixed(2)} | ${ww}W/${ll}L');
        }),
        if (_marketAnalysis != null) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🌍 حالة السوق العامة:',
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _indRow('النظام', MarketRegimeAnalyzer.regimeName(_marketAnalysis!.regime)),
          _indRow('اتجاه BTC 30 شمعة', '${_marketAnalysis!.btcTrendPct.toStringAsFixed(2)}%'),
          _indRow('اتجاه العملات البديلة', '${_marketAnalysis!.altTrendPct.toStringAsFixed(2)}%'),
          _indRow('Altseason Score', _marketAnalysis!.altseasonScore.toStringAsFixed(1)),
          _indRow('Dominance Proxy', _marketAnalysis!.btcDominanceProxy.toStringAsFixed(1)),
          const SizedBox(height: 4),
          Text(_marketAnalysis!.description,
              style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
        ],"""
if old_card_end in src:
    src = src.replace(old_card_end, new_card_end)
    checks.append(('market card', '🌍 حالة السوق العامة' in src))
else:
    checks.append(('market card', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Main Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('==================')
