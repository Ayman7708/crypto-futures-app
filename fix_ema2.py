# ============ indicators_v2.dart ============
with open('lib/indicators_v2.dart', 'r', encoding='utf-8') as f:
    v2 = f.read()

# Replace ALL _ema( and _emaSeries( occurrences (definitions + calls)
v2 = v2.replace('_emaSeries(', 'emaSeriesCalc(')
v2 = v2.replace('_ema(', 'emaCalc(')
v2 = v2.replace('_sma(', 'smaCalc(')

with open('lib/indicators_v2.dart', 'w', encoding='utf-8') as f:
    f.write(v2)

# ============ indicators_v3.dart ============
with open('lib/indicators_v3.dart', 'r', encoding='utf-8') as f:
    v3 = f.read()
v3 = v3.replace('_emaSeries(', 'emaSeriesCalc(')
v3 = v3.replace('_ema(', 'emaCalc(')
v3 = v3.replace('_sma(', 'smaCalc(')
with open('lib/indicators_v3.dart', 'w', encoding='utf-8') as f:
    f.write(v3)

# ============ master_signal.dart ============
with open('lib/master_signal.dart', 'r', encoding='utf-8') as f:
    ms = f.read()
ms = ms.replace('IndicatorsV2._ema(', 'IndicatorsV2.emaCalc(')
ms = ms.replace('IndicatorsV2._emaSeries(', 'IndicatorsV2.emaSeriesCalc(')
ms = ms.replace('IndicatorsV2._sma(', 'IndicatorsV2.smaCalc(')
with open('lib/master_signal.dart', 'w', encoding='utf-8') as f:
    f.write(ms)

# ============ Verify ============
print('=== تحقق ===')
for fn in ['lib/indicators_v2.dart', 'lib/indicators_v3.dart', 'lib/master_signal.dart']:
    with open(fn, 'r', encoding='utf-8') as fp:
        c = fp.read()
    bad = c.count('_ema(') + c.count('_emaSeries(') + c.count('_sma(')
    print(f'  {fn}: {bad} مراجع خاصة متبقية')

# Show sample of the fixed file
with open('lib/indicators_v2.dart', 'r', encoding='utf-8') as f:
    c = f.read()
import re
print('\n=== عينة من indicators_v2.dart ===')
for i, line in enumerate(c.split('\n'), 1):
    if 'emaCalc' in line or 'emaSeriesCalc' in line:
        print(f'  {i}: {line.strip()[:80]}')
        if i > 30: break
