with open('lib/market_regime.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Replace all `: 0,` with `: 0.0,` in MarketAnalysis constructor calls
src = src.replace(
    "btcTrendPct: 0, altTrendPct: 0, altseasonScore: 0,",
    "btcTrendPct: 0.0, altTrendPct: 0.0, altseasonScore: 0.0,"
)
src = src.replace(
    "btcDominanceProxy: 0, description:",
    "btcDominanceProxy: 0.0, description:"
)

with open('lib/market_regime.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/market_regime.dart', 'r', encoding='utf-8') as f:
    final = f.read()

if ': 0,' in final:
    print("⚠️ Still has : 0,")
    for i, line in enumerate(final.split('\n'), 1):
        if ': 0,' in line:
            print(f"  Line {i}: {line.strip()}")
else:
    print("✅ All : 0, replaced with : 0.0,")
