with open('lib/main.dart', 'r') as f:
    src = f.read()

checks = []

# 1. Add imports
if "import 'advanced.dart';" not in src:
    src = src.replace(
        "import 'services.dart';",
        "import 'services.dart';\nimport 'advanced.dart';\nimport 'api_candles.dart';"
    )
checks.append(('imports', "import 'advanced.dart';" in src))

# 2. Add state variables
old_state = "final Map<String, List<double>> _lowHistory = {};"
new_state = ("final Map<String, List<double>> _lowHistory = {};\n"
             "  final Map<String, List<double>> _volumeHistory = {};\n"
             "  List<IndicatorDef> _indicators = IndicatorRegistry.defaults();\n"
             "  bool _longBias = true;\n"
             "  final Map<String, double> _pumpScores = {};")
if "_volumeHistory" not in src:
    src = src.replace(old_state, new_state)
checks.append(('state vars', "_volumeHistory" in src))

# 3. initState volume history
old_init = "      _lowHistory[s] = [];\n    }"
new_init = "      _lowHistory[s] = [];\n      _volumeHistory[s] = [];\n    }"
if "      _volumeHistory[s] = [];" not in src:
    src = src.replace(old_init, new_init)
checks.append(('init volume', "_volumeHistory[s] = [];" in src))

# 4. TabController length 5 -> 7
src = src.replace("TabController(length: 5,", "TabController(length: 7,")
checks.append(('tabs 7', "TabController(length: 7," in src))

# 5. Replace _tick body
old_tick = """    final prices = await ApiService.fetchPrices(SYMBOLS);
    if (prices == null) {
      if (mounted) setState(() => _lastError = 'API error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _lastError = '';
      _livePrices.addAll(prices);
      for (final sym in SYMBOLS) {
        final p = prices[sym];
        if (p == null) continue;
        _priceHistory[sym]!.add(p);
        _highHistory[sym]!.add(p * 1.001);
        _lowHistory[sym]!.add(p * 0.999);
        if (_priceHistory[sym]!.length > 200) {
          _priceHistory[sym]!.removeAt(0);
          _highHistory[sym]!.removeAt(0);
          _lowHistory[sym]!.removeAt(0);
        }
        _process(sym, p);
      }
    });
    _saveState();"""

new_tick = """    final candles = await CandleService.fetchAll(SYMBOLS);
    if (candles == null) {
      if (mounted) setState(() => _lastError = 'API error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _lastError = '';
      for (final sym in SYMBOLS) {
        final c = candles[sym];
        if (c == null || c.isEmpty) continue;
        final last = c.last;
        _livePrices[sym] = last.close;
        _priceHistory[sym]!.add(last.close);
        _highHistory[sym]!.add(last.high);
        _lowHistory[sym]!.add(last.low);
        _volumeHistory[sym]!.add(last.volume);
        if (_priceHistory[sym]!.length > 200) {
          _priceHistory[sym]!.removeAt(0);
          _highHistory[sym]!.removeAt(0);
          _lowHistory[sym]!.removeAt(0);
          _volumeHistory[sym]!.removeAt(0);
        }
        _process(sym, last.close);
      }
    });
    _saveState();"""
if old_tick in src:
    src = src.replace(old_tick, new_tick)
checks.append(('tick', "CandleService.fetchAll" in src))

# 6. Replace _process body
old_proc = """    final ss = Indicators.sma(hist, _smaShort);
    final sl = Indicators.sma(hist, _smaLong);
    final rsi = Indicators.rsi(hist, 14);
    if (ss == null || sl == null || rsi == null) return;
    final scalp = ScalpAnalyzer.analyze(
      closes: hist, highs: _highHistory[symbol]!, lows: _lowHistory[symbol]!,
      smaShort: _smaShort, smaLong: _smaLong, rsiBuy: _rsiBuy,
    );
    _scalpSignals[symbol] = scalp;
    if (pos != null) {
      if (ss < sl && rsi > _rsiSell) _closePosition(symbol, price, 'SELL');
      return;
    }
    if (_balance < _marginPerTrade) return;
    if (_scalpEnabled && scalp.direction == 'LONG' && scalp.score >= _scalpThreshold) {
      _openPosition(symbol, price, isScalp: true);
      return;
    }
    if (ss > sl && rsi < _rsiBuy) _openPosition(symbol, price, isScalp: false);"""

new_proc = """    final ss = Indicators.sma(hist, _smaShort);
    final sl = Indicators.sma(hist, _smaLong);
    final rsi = Indicators.rsi(hist, 14);
    if (ss == null || sl == null || rsi == null) return;

    final thr = LearningEngine.adaptiveThreshold(_trades, _scalpThreshold);
    final signal = AdvancedAnalyzer.analyze(
      closes: hist,
      highs: _highHistory[symbol]!,
      lows: _lowHistory[symbol]!,
      volumes: _volumeHistory[symbol]!,
      smaShort: _smaShort,
      smaLong: _smaLong,
      rsiBuy: _rsiBuy,
      rsiSell: _rsiSell,
      pumpMinScore: 50,
      scalpMinScore: _longBias ? 55 : thr,
    );
    _scalpSignals[symbol] = ScalpSignal(signal.score, signal.direction, signal.reason);
    _pumpScores[symbol] = signal.pumpProb;

    if (pos != null) {
      if (rsi > 75 || (ss < sl && rsi > 70)) {
        _closePosition(symbol, price, 'SELL');
      }
      return;
    }
    if (_balance < _marginPerTrade) return;

    if (_longBias) {
      if (signal.direction == 'LONG' && signal.score >= 55) {
        _openPosition(symbol, price, isScalp: signal.score >= 70);
        for (final ind in _indicators) {
          ind.tests++;
          if (signal.score >= 70) ind.wins++;
        }
      }
    } else {
      if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= thr) {
        _openPosition(symbol, price, isScalp: true);
        return;
      }
      if (ss > sl && rsi < _rsiBuy) _openPosition(symbol, price, isScalp: false);
    }
    LearningEngine.updateWeights(_indicators, _trades);"""
if old_proc in src:
    src = src.replace(old_proc, new_proc)
checks.append(('process', "AdvancedAnalyzer.analyze" in src))

# 7. Add 2 tabs in TabBar
old_tb = """          tabs: const [
            Tab(text: 'Main'), Tab(text: 'Analysis'),
            Tab(text: 'History'), Tab(text: 'Backtest'), Tab(text: 'Settings'),
          ],"""
new_tb = """          tabs: const [
            Tab(text: 'Main'), Tab(text: 'Analysis'),
            Tab(text: 'History'), Tab(text: 'Backtest'), Tab(text: 'Testing'),
            Tab(text: 'Approved'), Tab(text: 'Settings'),
          ],"""
if old_tb in src:
    src = src.replace(old_tb, new_tb)
checks.append(('tabbar', "Tab(text: 'Testing')" in src))

# 8. Add 2 TabBarView children
old_children = """          _buildDashboard(), _buildAnalytics(), _buildTrades(),
          _buildBacktest(), _buildSettings(),"""
new_children = """          _buildDashboard(), _buildAnalytics(), _buildTrades(),
          _buildBacktest(), _buildTestingIndicators(), _buildApprovedIndicators(),
          _buildSettings(),"""
if old_children in src:
    src = src.replace(old_children, new_children)
checks.append(('children', "_buildTestingIndicators()" in src))

# 9. Insert new methods before _buildSettings
insert_pt = "  Widget _buildSettings() {"
new_methods = """  Widget _buildTestingIndicators() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _indicators.length,
      itemBuilder: (context, i) {
        final ind = _indicators[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ind.approved ? const Color(0xFF16A34A) : const Color(0xFF1E2838)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(ind.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ind.winRate >= 55 ? const Color(0xFF16A34A).withOpacity(0.2) : const Color(0xFF1A2332),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${ind.winRate.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: ind.winRate >= 55 ? const Color(0xFF4ADE80) : const Color(0xFF8892A6))),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${ind.platform} | ${ind.category}',
                style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Tests: ${ind.tests} | W: ${ind.wins} L: ${ind.losses}',
                  style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11)),
              TextButton(
                onPressed: () => setState(() { ind.approved = !ind.approved; _saveState(); }),
                child: Text(ind.approved ? 'Remove' : 'Approve',
                    style: TextStyle(color: ind.approved ? const Color(0xFFEF4444) : const Color(0xFF4ADE80), fontSize: 12)),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _buildApprovedIndicators() {
    final approved = _indicators.where((i) => i.approved).toList();
    if (approved.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No approved indicators yet.',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF4B5563))),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: approved.length,
      itemBuilder: (context, i) {
        final ind = approved[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF16A34A)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ind.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${ind.platform} | ${ind.winRate.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            ]),
            Text('W: ${ind.weight.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12)),
          ]),
        );
      },
    );
  }

  Widget _buildSettings() {"""
if insert_pt in src and "_buildTestingIndicators() {" not in src.split(insert_pt)[0][-200:]:
    src = src.replace(insert_pt, new_methods, 1)
checks.append(('methods', "Widget _buildTestingIndicators()" in src))

# 10. Save indicators in _saveState
old_save = """        'scalpEnabled': _scalpEnabled, 'apiKey': _apiKey, 'apiSecret': _apiSecret,
      },
    );"""
new_save = """        'scalpEnabled': _scalpEnabled, 'apiKey': _apiKey, 'apiSecret': _apiSecret,
        'longBias': _longBias,
        'indicators': _indicators.map((i) => i.toJson()).toList(),
      },
    );"""
if old_save in src:
    src = src.replace(old_save, new_save)
checks.append(('save indicators', "'longBias': _longBias" in src))

# 11. Load indicators in _loadState
old_load = "        _apiSecret = (s['apiSecret'] as String?) ?? '';"
new_load = """        _apiSecret = (s['apiSecret'] as String?) ?? '';
        _longBias = (s['longBias'] as bool?) ?? true;
        if (s['indicators'] != null) {
          final list = (s['indicators'] as List).map((e) => IndicatorDef.fromJson(e as Map<String, dynamic>)).toList();
          if (list.isNotEmpty) _indicators = list;
        }"""
if old_load in src:
    src = src.replace(old_load, new_load)
checks.append(('load indicators', "_longBias = (s['longBias'] as bool?)" in src))

# 12. LONG bias toggle in settings
old_sec = "        _sectionTitle('Scalping'),"
new_sec = """        _sectionTitle('Trading Mode'),
        SwitchListTile(
          value: _longBias, onChanged: (v) => setState(() => _longBias = v),
          title: const Text('LONG Bias (Buy heavy)', style: TextStyle(fontSize: 14)),
          subtitle: const Text('Prefer opening BUY positions', style: TextStyle(fontSize: 11)),
          activeColor: const Color(0xFF4ADE80),
        ),
        const SizedBox(height: 8),
        _sectionTitle('Scalping'),"""
if old_sec in src:
    src = src.replace(old_sec, new_sec, 1)
checks.append(('LONG toggle', "LONG Bias (Buy heavy)" in src))

with open('lib/main.dart', 'w') as f:
    f.write(src)

print('=== Patch Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
