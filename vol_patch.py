with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) import
if "import 'volatility.dart';" not in src:
    src = src.replace(
        "import 'market_regime.dart';",
        "import 'market_regime.dart';\nimport 'volatility.dart';"
    )
checks.append(('import', "import 'volatility.dart';" in src))

# 2) State field
target = "  MarketAnalysis? _marketAnalysis;"
new_field = """  MarketAnalysis? _marketAnalysis;
  final Map<String, VolatilityScore> _volScores = {};
  bool _focusFastCoins = true;
  int _topCoinCount = 10;"""
if "final Map<String, VolatilityScore> _volScores" not in src and target in src:
    src = src.replace(target, new_field, 1)
    checks.append(('state field', '_volScores' in src))
else:
    checks.append(('state field', '_volScores' in src))

# 3) Compute volatility in _tick — after market regime analysis
old_tick_end = """        _marketAnalysis = MarketRegimeAnalyzer.analyze(
          btcCloses: btcHist, altCloses: altMap,
        );
      }
    });"""
new_tick_end = """        _marketAnalysis = MarketRegimeAnalyzer.analyze(
          btcCloses: btcHist, altCloses: altMap,
        );
      }
      // Compute volatility score for every symbol
      for (final sym in SYMBOLS) {
        final h = _priceHistory[sym];
        final hh = _highHistory[sym];
        final ll = _lowHistory[sym];
        final vv = _volumeHistory[sym];
        if (h == null || hh == null || ll == null || vv == null) continue;
        if (h.length < 20) continue;
        _volScores[sym] = VolatilityRanker.analyze(
          symbol: sym, closes: h, highs: hh, lows: ll, volumes: vv,
        );
      }
    });"""
if old_tick_end in src and '_volScores[sym] = VolatilityRanker' not in src:
    src = src.replace(old_tick_end, new_tick_end)
    checks.append(('tick vol', '_volScores[sym] = VolatilityRanker' in src))
else:
    checks.append(('tick vol', '_volScores[sym] = VolatilityRanker' in src))

# 4) Add focus check in _process — before opening
old_open_check = """    final canTakeMore = _positions.length < _maxPositions && _canTradeSymbol(symbol);"""
new_open_check = """    final canTakeMore = _positions.length < _maxPositions && _canTradeSymbol(symbol);

    // Fast coins filter: only trade top N volatile coins if enabled
    bool isTopCoin = true;
    if (_focusFastCoins && _volScores.isNotEmpty) {
      final top = VolatilityRanker.topSymbols(_volScores, _topCoinCount);
      isTopCoin = top.contains(symbol);
    }"""
if old_open_check in src and 'isTopCoin' not in src:
    src = src.replace(old_open_check, new_open_check)
    checks.append(('top coin check', 'isTopCoin' in src))
else:
    checks.append(('top coin check', 'isTopCoin' in src))

# 5) Apply isTopCoin to entry conditions
src = src.replace(
    "final longOK = signal.score >= effectiveThreshold &&\n                   longMult > 0.5 &&\n                   learnedOK && canTakeMore;",
    "final longOK = signal.score >= effectiveThreshold &&\n                   longMult > 0.5 &&\n                   learnedOK && canTakeMore && isTopCoin;"
)
src = src.replace(
    "final shortOK = shortScore >= effectiveThresholdShort &&\n                    shortMult > 0.5 &&\n                    canTakeMore &&",
    "final shortOK = shortScore >= effectiveThresholdShort &&\n                    shortMult > 0.5 &&\n                    canTakeMore && isTopCoin &&"
)
checks.append(('apply top filter', 'canTakeMore && isTopCoin' in src))

# 6) Add volatility card in analysis section
old_card_end = """        if (_marketAnalysis != null) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🌍 حالة السوق العامة:',"""
new_card_end = """        if (_volScores.isNotEmpty) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🔥 ترتيب العملات حسب السرعة:',
              style: TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...(() {
            final sorted = _volScores.values.toList()
              ..sort((a, b) => b.opportunity.compareTo(a.opportunity));
            return sorted.take(10).map((v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text(VolatilityRanker.rankEmoji(v.rank),
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(v.symbol.replaceAll('USDT', ''),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                  Text('${v.opportunity.toStringAsFixed(0)} | ATR:${v.atrPct.toStringAsFixed(2)}% | Vol:${v.volumeSurge.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ));
          })(),
        ],
        if (_marketAnalysis != null) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🌍 حالة السوق العامة:',"""
if old_card_end in src and '🔥 ترتيب العملات حسب السرعة' not in src:
    src = src.replace(old_card_end, new_card_end)
    checks.append(('vol card', '🔥 ترتيب العملات حسب السرعة' in src))
else:
    checks.append(('vol card', '🔥 ترتيب العملات حسب السرعة' in src))

# 7) Add settings toggle for focus mode
old_settings = "        _sectionTitle('الإسكالبينج'),"
new_settings = """        _sectionTitle('التركيز على العملات السريعة'),
        SwitchListTile(
          value: _focusFastCoins,
          onChanged: (v) => setState(() => _focusFastCoins = v),
          title: const Text('تفعيل التركيز على العملات السريعة', style: TextStyle(fontSize: 14)),
          subtitle: const Text('يتداول فقط أعلى العملات تحركاً', style: TextStyle(fontSize: 11)),
          activeColor: const Color(0xFFFF6B35),
        ),
        _settingRow('عدد العملات المُختارة', '$_topCoinCount من ${SYMBOLS.length}',
            (v) => setState(() => _topCoinCount = int.tryParse(v) ?? _topCoinCount)),
        const SizedBox(height: 8),
        _sectionTitle('الإسكالبينج'),"""
if old_settings in src and 'التركيز على العملات السريعة' not in src:
    src = src.replace(old_settings, new_settings, 1)
    checks.append(('focus settings', 'التركيز على العملات السريعة' in src))
else:
    checks.append(('focus settings', 'التركيز على العملات السريعة' in src))

# 8) Save/load focus settings
old_save = "'master': _master.toJson(),"
new_save = "'master': _master.toJson(),\n        'focusFast': _focusFastCoins,\n        'topCoinCount': _topCoinCount,"
if old_save in src and "'focusFast': _focusFastCoins" not in src:
    src = src.replace(old_save, new_save)
    checks.append(('save focus', "'focusFast': _focusFastCoins" in src))
else:
    checks.append(('save focus', "'focusFast': _focusFastCoins" in src))

old_load = "        if (s['master'] != null) {\n          _master.loadFromJson(Map<String, dynamic>.from(s['master']));\n        }"
new_load = """        if (s['master'] != null) {
          _master.loadFromJson(Map<String, dynamic>.from(s['master']));
        }
        _focusFastCoins = (s['focusFast'] as bool?) ?? true;
        _topCoinCount = (s['topCoinCount'] as num?)?.toInt() ?? 10;"""
if old_load in src and "s['focusFast']" not in src:
    src = src.replace(old_load, new_load)
    checks.append(('load focus', "s['focusFast']" in src))
else:
    checks.append(('load focus', "s['focusFast']" in src))

# 9) Show volatility rank badge in dashboard coin card
old_dash = """                Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(price != null ? '\\$${price.toStringAsFixed(2)}' : '...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: Color(0xFF60A5FA))),"""
new_dash = """                Row(children: [
                  if (_volScores[sym] != null)
                    Text('${VolatilityRanker.rankEmoji(_volScores[sym]!.rank)} ',
                        style: const TextStyle(fontSize: 13)),
                  Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                Text(price != null ? '\\$${price.toStringAsFixed(2)}' : '...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: Color(0xFF60A5FA))),"""
if old_dash in src and 'VolatilityRanker.rankEmoji(_volScores[sym]!.rank)' not in src:
    src = src.replace(old_dash, new_dash)
    checks.append(('dashboard badge', 'VolatilityRanker.rankEmoji(_volScores[sym]!.rank)' in src))
else:
    checks.append(('dashboard badge', 'VolatilityRanker.rankEmoji(_volScores[sym]!.rank)' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Volatility Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('========================')
