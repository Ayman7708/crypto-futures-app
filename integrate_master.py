with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Import
if "import 'master_signal.dart';" not in src:
    src = src.replace(
        "import 'market_symbols.dart';",
        "import 'market_symbols.dart';\nimport 'master_signal.dart';"
    )
checks.append(('import', "import 'master_signal.dart';" in src))

# 2) State field
target = "  final Map<String, VolatilityScore> _volScores = {};"
new_field = """  final Map<String, VolatilityScore> _volScores = {};
  final MasterSignal _masterSignal = MasterSignal();
  final Map<String, MasterSignalResult> _masterResults = {};"""
if "final MasterSignal _masterSignal" not in src and target in src:
    src = src.replace(target, new_field, 1)
    checks.append(('state field', '_masterSignal' in src))
else:
    checks.append(('state field', '_masterSignal' in src))

# 3) Run master signal analysis in _tick
old_tick_end = """        _volScores[sym] = VolatilityRanker.analyze(
          symbol: sym, closes: h, highs: hh, lows: ll, volumes: vv,
        );
      }
    });"""

new_tick_end = """        _volScores[sym] = VolatilityRanker.analyze(
          symbol: sym, closes: h, highs: hh, lows: ll, volumes: vv,
        );
        // Master signal analysis
        if (h.length >= 55) {
          _masterResults[sym] = _masterSignal.analyze(
            closes: h, highs: hh, lows: ll, volumes: vv,
            smaShort: _smaShort, smaLong: _smaLong,
          );
        }
      }
    });"""
if old_tick_end in src and '_masterResults[sym] = _masterSignal.analyze' not in src:
    src = src.replace(old_tick_end, new_tick_end)
    checks.append(('tick analysis', '_masterResults[sym] = _masterSignal.analyze' in src))
else:
    checks.append(('tick analysis', '_masterResults[sym] = _masterSignal.analyze' in src))

# 4) Use master signal in _process — combine with existing signal
old_signal = """    var signal = AdvancedAnalyzer.analyze(
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
    );"""

new_signal = """    var signal = AdvancedAnalyzer.analyze(
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

    // === Master Signal: 40+ indicators vote ===
    final masterRes = _masterResults[symbol];
    if (masterRes != null) {
      final masterBull = masterRes.bullishScore;
      final masterBear = masterRes.bearishScore;
      // Blend: 30% old signal + 70% master
      if (masterBull > masterBear) {
        final blended = (signal.score * 0.3 + masterBull * 0.7).toInt();
        signal = AdvancedSignal(
          masterRes.recommendation.contains('LONG') ? 'LONG' : 'NONE',
          blended,
          '${signal.reason} | M:${masterRes.topBullish.take(3).join(",")}',
          signal.pumpProb,
        );
      } else {
        final blended = (signal.score * 0.3 + masterBear * 0.7).toInt();
        signal = AdvancedSignal(
          masterRes.recommendation.contains('SHORT') ? 'SHORT' : 'NONE',
          blended,
          '${signal.reason} | M:${masterRes.topBearish.take(3).join(",")}',
          signal.pumpProb,
        );
      }
    }"""

if old_signal in src and 'Master Signal: 40+ indicators vote' not in src:
    src = src.replace(old_signal, new_signal)
    checks.append(('process blend', 'Master Signal: 40+ indicators vote' in src))
else:
    checks.append(('process blend', 'Master Signal: 40+ indicators vote' in src))

# 5) Update master signal on trade close
old_close = """    // Update each master strategy weight
    for (final s in _master.strategies) {
      _master.updateFromTrade(s.name, wasWin);
    }"""
new_close = """    // Update each master strategy weight
    for (final s in _master.strategies) {
      _master.updateFromTrade(s.name, wasWin);
    }
    // Update master signal indicator weights
    final mr = _masterResults[symbol];
    if (mr != null) {
      _masterSignal.updateFromTrade(mr.votes, wasWin);
    }"""
if old_close in src and '_masterSignal.updateFromTrade' not in src:
    src = src.replace(old_close, new_close)
    checks.append(('update signal', '_masterSignal.updateFromTrade' in src))
else:
    checks.append(('update signal', '_masterSignal.updateFromTrade' in src))

# 6) Save master signal
old_save = "'topCoinCount': _topCoinCount,"
new_save = "'topCoinCount': _topCoinCount,\n        'masterSignal': _masterSignal.toJson(),"
if old_save in src and "'masterSignal': _masterSignal.toJson()" not in src:
    src = src.replace(old_save, new_save)
    checks.append(('save signal', "'masterSignal': _masterSignal.toJson()" in src))
else:
    checks.append(('save signal', "'masterSignal': _masterSignal.toJson()" in src))

# 7) Load master signal
old_load = "_topCoinCount = (s['topCoinCount'] as num?)?.toInt() ?? 10;"
new_load = """_topCoinCount = (s['topCoinCount'] as num?)?.toInt() ?? 10;
        if (s['masterSignal'] != null) {
          _masterSignal.loadFromJson(Map<String, dynamic>.from(s['masterSignal']));
        }"""
if old_load in src and "s['masterSignal']" not in src:
    src = src.replace(old_load, new_load)
    checks.append(('load signal', "s['masterSignal']" in src))
else:
    checks.append(('load signal', "s['masterSignal']" in src))

# 8) Add master signal card in learning section
old_learn_end = """        if (_volScores.isNotEmpty) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🔥 ترتيب العملات حسب السرعة:',"""
new_learn_end = """        Builder(builder: (context) {
          final btcMaster = _masterResults['BTCUSDT'];
          if (btcMaster == null) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(color: Color(0xFF1E2838)),
            const Text('👑 المؤشر الأسطوري (BTC)',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [
                const Text('صعودي', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
                Text('${btcMaster.bullishScore}',
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              Column(children: [
                const Text('هبوطي', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                Text('${btcMaster.bearishScore}',
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
            ]),
            const SizedBox(height: 4),
            Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: btcMaster.recommendation.contains('LONG')
                    ? const Color(0xFF16A34A).withOpacity(0.3)
                    : (btcMaster.recommendation.contains('SHORT')
                        ? const Color(0xFFDC2626).withOpacity(0.3)
                        : const Color(0xFF1A2332)),
                borderRadius: BorderRadius.circular(6)),
              child: Text(btcMaster.recommendation,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            )),
            const SizedBox(height: 6),
            if (btcMaster.topBullish.isNotEmpty)
              Text('👆 ${btcMaster.topBullish.join(" • ")}',
                  style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10)),
            if (btcMaster.topBearish.isNotEmpty)
              Text('👇 ${btcMaster.topBearish.join(" • ")}',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10)),
          ]);
        }),
        if (_volScores.isNotEmpty) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🔥 ترتيب العملات حسب السرعة:',"""
if old_learn_end in src and '👑 المؤشر الأسطوري' not in src:
    src = src.replace(old_learn_end, new_learn_end)
    checks.append(('legendary card', '👑 المؤشر الأسطوري' in src))
else:
    checks.append(('legendary card', '👑 المؤشر الأسطوري' in src))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Integrate Master ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=======================')
