with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Add strategies card in learning card section
old = """        if (_learner.losingPatterns.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('🚫 أنماط خاسرة محفوظة: ${_learner.losingPatterns.length}',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
        ],"""
new = """        if (_learner.losingPatterns.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('🚫 أنماط خاسرة محفوظة: ${_learner.losingPatterns.length}',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
        ],
        const Divider(color: Color(0xFF1E2838)),
        const Text('⚙️ أوزان الاستراتيجيات:', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ..._master.strategies.map((s) {
          final w = _master.weights[s.name] ?? 1.0;
          final ww = _master.wins[s.name] ?? 0;
          final ll = _master.losses[s.name] ?? 0;
          return _indRow(s.name, 'W:${w.toStringAsFixed(2)} | ${ww}W/${ll}L');
        }),"""
if old in src:
    src = src.replace(old, new)
    checks.append(('strategy card', '⚙️ أوزان الاستراتيجيات' in src))
else:
    checks.append(('strategy card', False))

# Add top strategies to each coin tile
old2 = """        const Divider(color: Color(0xFF1E2838)),
        if (scalp != null) ...["""
new2 = """        const Divider(color: Color(0xFF1E2838)),
        if ((_masterTopStrategies[sym] ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('🎯 الاستراتيجيات: ${_masterTopStrategies[sym]}',
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
          ),
        if (scalp != null) ...["""
if old2 in src:
    src = src.replace(old2, new2)
    checks.append(('coin strategies', '🎯 الاستراتيجيات' in src))
else:
    checks.append(('coin strategies', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Show Strategies Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('============================')
