with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# 1) Add _topContributors declaration next to _scalpSignals
target = "  final Map<String, ScalpSignal> _scalpSignals = {};"
if 'final Map<String, List<String>> _topContributors' not in src:
    src = src.replace(
        target,
        target + "\n  final Map<String, List<String>> _topContributors = {};",
        1
    )
    print("✅ Added _topContributors declaration")

# 2) Make sure safe-null operator used
src = src.replace(
    "final activeNames = _topContributors[symbol] ?? [];",
    "final activeNames = _topContributors[symbol] ?? <String>[];"
)
print("✅ Safe null check")

# 3) Record top contributors when opening position
old_open = "_lastTradeTime[symbol] = DateTime.now();"
new_open = """_lastTradeTime[symbol] = DateTime.now();
    // Record top contributing indicators for learning
    final mr = _masterResults[symbol];
    if (mr != null) {
      _topContributors[symbol] = [
        ...mr.topBullish.take(5),
        ...mr.topBearish.take(5),
      ].map((e) => e.contains('(') ? e.split('(').first : e).toList();
    }"""
if '_topContributors[symbol] = [' not in src and old_open in src:
    src = src.replace(old_open, new_open, 1)
    print("✅ Record contributors on open")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

print()
print(f"✅ _topContributors declared: {'final Map<String, List<String>> _topContributors' in final}")
print(f"✅ _topContributors used: {final.count('_topContributors')}")
print(f"📊 Braces: {final.count('{')} open / {final.count('}')} close")
