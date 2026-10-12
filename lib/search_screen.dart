import 'package:flutter/material.dart';
import 'deep_analysis.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  DeepAnalysisResult? _result;
  String? _error;

  Future<void> _search() async {
    final raw = _controller.text.trim().toUpperCase();
    if (raw.isEmpty) return;
    final symbol = raw.endsWith('USDT') ? raw : '${raw}USDT';
    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final res = await DeepAnalyzer.analyze(symbol);
      if (!mounted) return;
      setState(() {
        _result = res;
        if (res == null) _error = 'لم يتم العثور على بيانات للعملة "$symbol"';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'خطأ: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF131A26),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'مثال: BTC أو BTCUSDT',
                hintStyle: const TextStyle(color: Color(0xFF8892A6)),
                filled: true, fillColor: const Color(0xFF0A0E17),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4ADE80),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: _loading ? null : _search,
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, color: Colors.black),
          ),
        ]),
      ),
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: Color(0xFF4ADE80)),
        SizedBox(height: 16),
        Text('جاري التحليل العميق...', style: TextStyle(color: Color(0xFF8892A6))),
      ]));
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(20),
        child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444)), textAlign: TextAlign.center)));
    }
    if (_result == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search, size: 60, color: Color(0xFF1E2838)),
          SizedBox(height: 12),
          Text('اكتب رمز عملة واضغط بحث\nمثال: BTC, ETH, SOL, CFX',
            style: TextStyle(color: Color(0xFF8892A6)), textAlign: TextAlign.center),
        ])));
    }
    return _buildResult(_result!);
  }

  Widget _buildResult(DeepAnalysisResult r) {
    final recColor = r.recommendation.contains('BUY') ? const Color(0xFF4ADE80)
        : r.recommendation.contains('SELL') ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return ListView(padding: const EdgeInsets.all(10), children: [
      // Header card
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1E3A2F), Color(0xFF16241C)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: recColor, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(r.symbol, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('\$${r.currentPrice.toStringAsFixed(4)}',
              style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _scoreBox('صعود', r.overallBull, const Color(0xFF4ADE80)),
            _scoreBox('هبوط', r.overallBear, const Color(0xFFEF4444)),
          ]),
          const SizedBox(height: 12),
          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: recColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: recColor)),
            child: Text(_recLabel(r.recommendation),
              style: TextStyle(color: recColor, fontSize: 16, fontWeight: FontWeight.bold)),
          )),
        ]),
      ),
      const SizedBox(height: 10),

      // Entry/Exit
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E2838))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📍 مناطق التداول المقترحة', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _row('أفضل دخول شراء', '\$${r.bestBuy.toStringAsFixed(4)}', const Color(0xFF4ADE80)),
          _row('أفضل خروج بيع', '\$${r.bestSell.toStringAsFixed(4)}', const Color(0xFFEF4444)),
          _row('وقف الخسارة', '\$${r.stopLoss.toStringAsFixed(4)}', const Color(0xFFDC2626)),
          _row('الهدف (TP)', '\$${r.takeProfit.toStringAsFixed(4)}', const Color(0xFF16A34A)),
        ]),
      ),
      const SizedBox(height: 10),

      // Timeframes
      const Text('📊 التحليل حسب الفريمات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 6),
      for (final iv in ['1m', '5m', '15m', '1h'])
        if (r.timeframes.containsKey(iv)) _tfCard(r.timeframes[iv]!),
      const SizedBox(height: 10),

      // Patterns
      if (r.keyPatterns.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E2838))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🕯️ الأنماط المكتشفة', style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: r.keyPatterns.map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF1A2332), borderRadius: BorderRadius.circular(6)),
              child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 11)),
            )).toList()),
          ]),
        ),
    ]);
  }

  Widget _scoreBox(String label, int val, Color color) {
    return Column(children: [
      Text(label, style: TextStyle(color: color, fontSize: 11)),
      Text('$val', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      Text('/100', style: TextStyle(color: color.withOpacity(0.5), fontSize: 10)),
    ]);
  }

  Widget _row(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _tfCard(TimeframeAnalysis tf) {
    final trendColor = tf.trend == 'BULL' ? const Color(0xFF4ADE80)
        : tf.trend == 'BEAR' ? const Color(0xFFEF4444)
        : const Color(0xFF8892A6);
    final nextIcon = tf.nextCandle == 'GREEN' ? '🟢 خضراء'
        : tf.nextCandle == 'RED' ? '🔴 حمراء'
        : '🕯️ دوجي';
    final nextColor = tf.nextCandle == 'GREEN' ? const Color(0xFF4ADE80)
        : tf.nextCandle == 'RED' ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trendColor.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: trendColor.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
            child: Text(tf.interval, style: TextStyle(color: trendColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Row(children: [
            Text(nextIcon, style: TextStyle(color: nextColor, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Text('(${tf.nextConfidence}%)', style: TextStyle(color: nextColor.withOpacity(0.7), fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('صعود: ${tf.bullScore}', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.bold)),
          Text('هبوط: ${tf.bearScore}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        _row('الدعم', '\$${tf.support.toStringAsFixed(4)}', const Color(0xFF16A34A)),
        _row('المقاومة', '\$${tf.resistance.toStringAsFixed(4)}', const Color(0xFFDC2626)),
        if (tf.patterns.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: tf.patterns.take(4).map((p) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF1A2332), borderRadius: BorderRadius.circular(4)),
            child: Text(p, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
          )).toList()),
        ],
      ]),
    );
  }

  String _recLabel(String rec) {
    switch (rec) {
      case 'STRONG_BUY': return '🚀 شراء قوي';
      case 'BUY': return '🟢 شراء';
      case 'STRONG_SELL': return '🔻 بيع قوي';
      case 'SELL': return '🔴 بيع';
      default: return '⏸️ انتظار';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
