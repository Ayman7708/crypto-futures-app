with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Insert learning card at top of analytics list
old_analytics_head = """  Widget _buildAnalytics() {
    return ListView.builder(
      padding: const EdgeInsets.all(10), itemCount: SYMBOLS.length,
      itemBuilder: (context, i) {"""
new_analytics_head = """  Widget _buildAnalytics() {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _buildLearningCard(),
        const SizedBox(height: 10),
        ...SYMBOLS.map((sym) => _buildAnalyticsTile(sym)),
      ],
    );
  }

  Widget _buildLearningCard() {
    final wr = _learner.totalTrades == 0 ? 0.0 : (_learner.totalWins / _learner.totalTrades * 100);
    final top = _learner.getTopIndicators(limit: 3);
    final worst = _learner.getWorstIndicators(limit: 3);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E2838), Color(0xFF131A26)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF60A5FA), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('🧠 نظام التعلم الذكي',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF60A5FA))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17), borderRadius: BorderRadius.circular(6)),
            child: Text(_learner.regimeName,
                style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80))),
          ),
        ]),
        const SizedBox(height: 10),
        _indRow('إجمالي الصفقات', '${_learner.totalTrades}'),
        _indRow('الرابحة / الخاسرة', '${_learner.totalWins} / ${_learner.totalLosses}'),
        _indRow('نسبة النجاح', '${wr.toStringAsFixed(1)}%'),
        _indRow('عتبة الدخول الحالية', '${_learner.entryThreshold.toStringAsFixed(0)}/100'),
        _indRow('الربح التراكمي', '\$${_learner.rollingPnL.toStringAsFixed(2)}'),
        const Divider(color: Color(0xFF1E2838)),
        if (top.isNotEmpty) ...[
          const Text('🏆 أفضل المؤشرات:', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final p in top)
            _indRow(p.id, '${(p.winRate * 100).toStringAsFixed(0)}% (W:${p.wins} L:${p.losses})'),
          const SizedBox(height: 8),
        ],
        if (worst.isNotEmpty) ...[
          const Text('⚠️ أسوأ المؤشرات:', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final p in worst)
            _indRow(p.id, '${(p.winRate * 100).toStringAsFixed(0)}% (W:${p.wins} L:${p.losses})'),
        ],
        if (_learner.losingPatterns.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('🚫 أنماط خاسرة محفوظة: ${_learner.losingPatterns.length}',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildAnalyticsTile(String sym) {
    final hist = _priceHistory[sym]!;
    if (hist.length < 30) return _card('$sym', 'Analyzing... (${hist.length}/30)');
    final rsi = Indicators.rsi(hist, 14);
    final (macd, signal, histogram) = Indicators.macd(hist);
    final (lowBB, midBB, upBB) = Indicators.bollinger(hist);
    final stoch = Indicators.stochastic(_highHistory[sym]!, _lowHistory[sym]!, hist, 14);
    final scalp = _scalpSignals[sym];
    final pump = _pumpScores[sym] ?? 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2838))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (pump >= 60)
            Text('🔥 ${pump.toInt()}%', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        _indRow('RSI (14)', rsi?.toStringAsFixed(2) ?? '-'),
        _indRow('MACD', macd?.toStringAsFixed(2) ?? '-'),
        _indRow('Signal', signal?.toStringAsFixed(2) ?? '-'),
        _indRow('Histogram', histogram?.toStringAsFixed(2) ?? '-'),
        _indRow('BB L/M/U',
            lowBB != null ? '${lowBB.toStringAsFixed(0)}/${midBB!.toStringAsFixed(0)}/${upBB!.toStringAsFixed(0)}' : '-'),
        _indRow('Stochastic', stoch?.toStringAsFixed(1) ?? '-'),
        const Divider(color: Color(0xFF1E2838)),
        if (scalp != null) ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Scalp Score', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scalp.score >= _scalpThreshold ? const Color(0xFF16A34A) : const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(6)),
              child: Text('${scalp.score}/100', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(scalp.reason, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildAnalyticsOld() {
    return ListView.builder(
      padding: const EdgeInsets.all(10), itemCount: SYMBOLS.length,
      itemBuilder: (context, i) {"""
if old_analytics_head in src:
    src = src.replace(old_analytics_head, new_analytics_head)
    checks.append(('analytics UI', '_buildLearningCard' in src))
else:
    checks.append(('analytics UI', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Patch Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
