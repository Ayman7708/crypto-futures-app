with open('lib/engine.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Add isLong field to Position
old_pos = """class Position {
  final String symbol;
  final double entry;
  final double size;
  final double margin;
  final double stopLoss;
  final double takeProfit;
  final int leverage;
  final bool isScalp;
  final DateTime openedAt;

  Position({
    required this.symbol, required this.entry, required this.size,
    required this.margin, required this.stopLoss, required this.takeProfit,
    required this.leverage, this.isScalp = false, DateTime? openedAt,
  }) : openedAt = openedAt ?? DateTime.now();

  double pnl(double current) => (current - entry) * size;
}"""

new_pos = """class Position {
  final String symbol;
  final double entry;
  final double size;
  final double margin;
  final double stopLoss;
  final double takeProfit;
  final int leverage;
  final bool isScalp;
  final bool isLong;
  final DateTime openedAt;

  Position({
    required this.symbol, required this.entry, required this.size,
    required this.margin, required this.stopLoss, required this.takeProfit,
    required this.leverage, this.isScalp = false, this.isLong = true,
    DateTime? openedAt,
  }) : openedAt = openedAt ?? DateTime.now();

  double pnl(double current) => isLong
      ? (current - entry) * size
      : (entry - current) * size;

  double get liquidationPrice => isLong
      ? entry * (1 - 1 / leverage)
      : entry * (1 + 1 / leverage);
}"""

if old_pos in src:
    src = src.replace(old_pos, new_pos)
    checks.append(('position isLong', 'final bool isLong;' in src))
else:
    checks.append(('position isLong', False))

with open('lib/engine.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Engine Patch ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('==================')
