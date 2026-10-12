with open('lib/master_signal.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Replace any remaining private calls
src = src.replace('IndicatorsV2._ema(', 'IndicatorsV2.emaCalc(')
src = src.replace('IndicatorsV2._emaSeries(', 'IndicatorsV2.emaSeriesCalc(')
src = src.replace('IndicatorsV2._sma(', 'IndicatorsV2.smaCalc(')

# Also without "IndicatorsV2." prefix (if any)
src = src.replace('_emaSeries(', 'emaSeriesCalc(')
src = src.replace('_ema(', 'emaCalc(')
src = src.replace('_sma(', 'smaCalc(')

with open('lib/master_signal.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/master_signal.dart', 'r', encoding='utf-8') as f:
    final = f.read()

remaining = final.count('_ema(') + final.count('_emaSeries(') + final.count('_sma(')
print(f'✅ Remaining: {remaining}')

if remaining > 0:
    import re
    for i, line in enumerate(final.split('\n'), 1):
        if '_ema(' in line or '_emaSeries(' in line or '_sma(' in line:
            print(f'  Line {i}: {line.strip()}')
