import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# === A: Fix profit time recording ===
if 'if (pnl > 0) _lastProfitTime' not in src:
    m = re.search(
        r'(void _closePosition\([^)]+\) \{.*?final pnl = \(price - pos\.entry\) \* pos\.size;)',
        src, re.DOTALL
    )
    if m:
        old = m.group(1)
        new = old + "\n    if (pnl > 0) _lastProfitTime[symbol] = DateTime.now();"
        src = src.replace(old, new, 1)
        checks.append(('profit time', 'if (pnl > 0) _lastProfitTime' in src))
    else:
        checks.append(('profit time', False))
else:
    checks.append(('profit time', True))

# === B: Add _statBox helper before _buildTrades ===
if 'Widget _statBox(' not in src:
    helper = """  Widget _statBox(String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
    ]);
  }

"""
    src = src.replace("  Widget _buildTrades() {", helper + "  Widget _buildTrades() {", 1)
    checks.append(('statBox helper', 'Widget _statBox(' in src))
else:
    checks.append(('statBox helper', True))

# === C: Replace _buildTrades with stats + entry/exit labels ===
start_marker = '  Widget _buildTrades() {'
end_marker = '  Widget _buildBacktest() {'
start_idx = src.find(start_marker)
end_idx = src.find(end_marker)

if start_idx > 0 and end_idx > start_idx:
    new_code = """  Widget _buildTrades() {
    final openCount = _positions.length;
    final closed = _trades.where((t) => t.pnl != 0).toList();
    final wins = closed.where((t) => t.pnl > 0).length;
    final losses = closed.where((t) => t.pnl < 0).length;
    final totalPnl = closed.fold<double>(0, (s, t) => s + t.pnl);
    final wr = closed.isEmpty ? 0.0 : (wins / closed.length * 100);

    return Column(children: [
      Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF131A26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF60A5FA)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statBox('مفتوحة', '$openCount', const Color(0xFF60A5FA)),
          _statBox('رابحة', '$wins', const Color(0xFF4ADE80)),
          _statBox('خاسرة', '$losses', const Color(0xFFEF4444)),
          _statBox('نجاح', '${wr.toStringAsFixed(0)}%', const Color(0xFFF59E0B)),
          _statBox('PnL', '${totalPnl >= 0 ? "+" : ""}\\$${totalPnl.toStringAsFixed(1)}',
            totalPnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444)),
        ]),
      ),
      Expanded(
        child: _trades.isEmpty
          ? const Center(child: Text('لا توجد صفقات بعد', style: TextStyle(color: Color(0xFF4B5563))))
          : ListView.builder(
              padding: const EdgeInsets.all(10), itemCount: _trades.length,
              itemBuilder: (context, i) {
                final t = _trades[i];
                Color color = const Color(0xFF4ADE80);
                String label = 'شراء';
                if (t.action == 'SELL') { color = const Color(0xFFEF4444); label = 'بيع'; }
                if (t.action == 'SCALP_BUY') { color = const Color(0xFFF59E0B); label = 'إسكالبينج'; }
                if (t.action == 'STOP_LOSS') { color = const Color(0xFFDC2626); label = 'وقف خسارة'; }
                if (t.action == 'TAKE_PROFIT') { color = const Color(0xFF16A34A); label = 'جني ربح'; }
                if (t.action == 'LIQUIDATED') { color = const Color(0xFFF59E0B); label = 'تصفية'; }
                if (t.action == 'MANUAL') { color = const Color(0xFF60A5FA); label = 'يدوي'; }
                final isEntry = t.action == 'BUY' || t.action == 'SCALP_BUY';
                final priceLabel = isEntry ? 'دخول' : 'خروج';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332), borderRadius: BorderRadius.circular(8),
                    border: Border(right: BorderSide(color: color, width: 3))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$label ${t.symbol}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} | $priceLabel: \\$${t.price.toStringAsFixed(4)}',
                          style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
                    ]),
                    if (t.pnl != 0)
                      Text('${t.pnl >= 0 ? '+' : ''}\\$${t.pnl.toStringAsFixed(2)}',
                          style: TextStyle(color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                              fontWeight: FontWeight.bold)),
                  ]),
                );
              },
            ),
      ),
    ]);
  }

"""
    src = src[:start_idx] + new_code + src[end_idx:]
    checks.append(('trade list rebuilt', "'مفتوحة'" in src and 'priceLabel' in src))
else:
    checks.append(('trade list rebuilt', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('===============')
