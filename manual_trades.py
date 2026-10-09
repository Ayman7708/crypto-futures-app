with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# ========== 1. Helper: sort symbols by pump score ==========
helper = """  List<String> get _sortedSymbols {
    final list = List<String>.from(SYMBOLS);
    list.sort((a, b) {
      final sa = _pumpScores[a] ?? 0;
      final sb = _pumpScores[b] ?? 0;
      return sb.compareTo(sa);
    });
    return list;
  }

"""
if '_sortedSymbols' not in src:
    src = src.replace(
        "  Future<void> _loadState() async {",
        helper + "  Future<void> _loadState() async {",
        1,
    )
checks.append(('sorted helper', '_sortedSymbols' in src))

# ========== 2. Manual open/close methods ==========
manual = """  void _manualOpen(String symbol) {
    final price = _livePrices[symbol];
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد سعر متاح حالياً'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    if (_positions.containsKey(symbol)) return;
    if (_balance < _marginPerTrade) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرصيد غير كافٍ'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    setState(() => _openPosition(symbol, price, isScalp: false));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم فتح صفقة على $symbol'), backgroundColor: const Color(0xFF16A34A)),
    );
  }

  void _manualClose(String symbol) {
    final pos = _positions[symbol];
    if (pos == null) return;
    final price = _livePrices[symbol] ?? pos.entry;
    setState(() => _closePosition(symbol, price, 'MANUAL'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إغلاق صفقة $symbol'), backgroundColor: const Color(0xFF16A34A)),
    );
  }

"""
if '_manualOpen' not in src:
    src = src.replace(
        "  void _openPosition(String symbol, double price, {required bool isScalp}) {",
        manual + "  void _openPosition(String symbol, double price, {required bool isScalp}) {",
        1,
    )
checks.append(('manual methods', '_manualOpen' in src))

# ========== 3. Dashboard: sort by pump score ==========
old_dash = """        padding: const EdgeInsets.all(10), itemCount: SYMBOLS.length,
        itemBuilder: (context, i) {
          final sym = SYMBOLS[i];"""
new_dash = """        padding: const EdgeInsets.all(10), itemCount: _sortedSymbols.length,
        itemBuilder: (context, i) {
          final sym = _sortedSymbols[i];"""
if old_dash in src:
    src = src.replace(old_dash, new_dash)
    checks.append(('dashboard sort', 'itemCount: _sortedSymbols.length' in src))
else:
    checks.append(('dashboard sort', False))

# ========== 4. Add `pump` variable in dashboard ==========
old_var = "          final scalp = _scalpSignals[sym];\n          return Container(\n            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),"
new_var = "          final scalp = _scalpSignals[sym];\n          final pump = _pumpScores[sym] ?? 0.0;\n          return Container(\n            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),"
if 'final pump = _pumpScores[sym]' not in src and old_var in src:
    src = src.replace(old_var, new_var)
    checks.append(('pump var', 'final pump = _pumpScores[sym]' in src))
else:
    checks.append(('pump var', 'final pump = _pumpScores[sym]' in src))

# ========== 5. Add buttons + badge to card ==========
old_tail = """              if (pos != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332),
                    border: Border(right: BorderSide(
                      color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), width: 3)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(pos.isScalp ? 'إسكالبينج' : 'مفتوح',
                        style: TextStyle(color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), fontSize: 12)),
                    Text('E: \\$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? "+" : ""}\\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11,
                            color: pos.pnl(price ?? pos.entry) >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444))),
                  ]),
                ),
              ],
            ]),"""

new_tail = """              if (pos != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332),
                    border: Border(right: BorderSide(
                      color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), width: 3)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(pos.isScalp ? 'إسكالبينج' : 'مفتوح',
                        style: TextStyle(color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), fontSize: 12)),
                    Text('E: \\$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? "+" : ""}\\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11,
                            color: pos.pnl(price ?? pos.entry) >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444))),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                if (pump >= 60)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('🔥 ${pump.toInt()}%',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                if (pos == null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.trending_up, size: 14, color: Colors.white),
                    label: const Text('فتح صفقة', style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: () => _manualOpen(sym),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close, size: 14, color: Colors.white),
                    label: const Text('إغلاق', style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: () => _manualClose(sym),
                  ),
              ]),
            ]),"""

if old_tail in src:
    src = src.replace(old_tail, new_tail)
    checks.append(('buttons + badge', 'فتح صفقة' in src))
else:
    checks.append(('buttons + badge', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Patch Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('=====================')
