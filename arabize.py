with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Dictionary of all replacements: (English text, Arabic text)
# Order matters - longer strings first to avoid partial replacements
repl = [
    # App title
    ("'Crypto Bot Pro v2'", "'بوت التداول برو v2'"),

    # Status
    ("_running ? 'ON' : 'OFF'", "_running ? 'يعمل' : 'متوقف'"),

    # Tabs
    ("Tab(text: 'Main')", "Tab(text: 'الرئيسية')"),
    ("Tab(text: 'Analysis')", "Tab(text: 'التحليل')"),
    ("Tab(text: 'History')", "Tab(text: 'السجل')"),
    ("Tab(text: 'Backtest')", "Tab(text: 'الاختبار')"),
    ("Tab(text: 'Testing')", "Tab(text: 'اختبار المؤشرات')"),
    ("Tab(text: 'Approved')", "Tab(text: 'المعتمدة')"),
    ("Tab(text: 'Settings')", "Tab(text: 'الإعدادات')"),

    # Balance bar
    ("'Balance'", "'الرصيد'"),
    ("'PnL'", "'الربح / الخسارة'"),

    # Dashboard
    ("'Scalp'", "'إسكالبينج'"),
    ("'Open'", "'مفتوح'"),
    ("pos.isScalp ? 'Scalp' : 'Open'", "pos.isScalp ? 'إسكالبينج' : 'مفتوح'"),

    # Analytics
    ("'Analyzing... (\\${hist.length}/30)'", "'جاري التحليل... (\\${hist.length}/30)'"),
    ("'RSI (14)'", "'RSI (14)'"),
    ("'Signal'", "'الإشارة'"),
    ("'Histogram'", "'الهستوجرام'"),
    ("'BB L/M/U'", "'بولنجر L/M/U'"),
    ("'Stochastic'", "'الستوكاستيك'"),
    ("'Scalp Score'", "'درجة الإسكالبينج'"),

    # Trades
    ("'No trades yet'", "'لا توجد صفقات بعد'"),
    ("label = 'BUY'", "label = 'شراء'"),
    ("label = 'SELL'", "label = 'بيع'"),
    ("label = 'SCALP'", "label = 'إسكالبينج'"),
    ("label = 'SL'", "label = 'وقف خسارة'"),
    ("label = 'TP'", "label = 'جني ربح'"),
    ("label = 'LIQ'", "label = 'تصفية'"),

    # Backtest
    ("'Backtest on collected data'", "'الاختبار على البيانات المجمعة'"),
    ("'Not enough data (\\${hist.length}/40)'", "'بيانات غير كافية (\\${hist.length}/40)'"),
    ("'Trades'", "'الصفقات'"),
    ("'Wins'", "'الرابحة'"),
    ("'Losses'", "'الخاسرة'"),
    ("'Final'", "'النهائي'"),
    ("'Profit'", "'الربح'"),
    ("'Max DD'", "'أقصى تراجع'"),

    # Testing indicators tab
    ("'No approved indicators yet.'", "'لا توجد مؤشرات معتمدة بعد'"),
    ("'Approve'", "'اعتماد'"),
    ("'Remove'", "'إزالة'"),

    # Settings - section titles
    ("_sectionTitle('Risk Management')", "_sectionTitle('إدارة المخاطر')"),
    ("_sectionTitle('Indicators')", "_sectionTitle('المؤشرات')"),
    ("_sectionTitle('Scalping')", "_sectionTitle('الإسكالبينج')"),
    ("_sectionTitle('Trading Mode')", "_sectionTitle('وضع التداول')"),
    ("_sectionTitle('Binance API')", "_sectionTitle('ربط Binance')"),

    # Settings - rows
    ("'Initial Capital'", "'رأس المال الأولي'"),
    ("'Margin per Trade'", "'الهامش لكل صفقة'"),
    ("'Leverage'", "'الرافعة المالية'"),
    ("'Stop Loss %'", "'وقف الخسارة %'"),
    ("'Take Profit %'", "'جني الربح %'"),
    ("'RSI Buy'", "'RSI الشراء'"),
    ("'RSI Sell'", "'RSI البيع'"),
    ("'SMA Short'", "'SMA القصير'"),
    ("'SMA Long'", "'SMA الطويل'"),
    ("'Min Score'", "'الحد الأدنى للدرجة'"),
    ("'API Key'", "'مفتاح API'"),
    ("'API Secret'", "'سر API'"),
    ("'Not set'", "'غير مضاف'"),

    # Settings - toggles
    ("'LONG Bias (Buy heavy)'", "'تفضيل الشراء (LONG Bias)'"),
    ("'Prefer opening BUY positions'", "'تفضيل فتح صفقات الشراء'"),
    ("'Auto Scalping'", "'الإسكالبينج التلقائي'"),

    # Settings - text
    ("'Simulation mode. Live trading coming soon.'", "'وضع المحاكاة. التداول الحي قادم قريباً'"),
    ("'Save Settings'", "'حفظ الإعدادات'"),
    ("'Saved'", "'تم الحفظ'"),
    ("'Reset All'", "'إعادة تعيين الكل'"),

    # Reset dialog
    ("'Reset'", "'إعادة تعيين'"),
    ("'Delete all trades and reset balance?'", "'حذف كل الصفقات وإعادة الرصيد؟'"),
    ("'Cancel'", "'إلغاء'"),
    ("'Yes'", "'نعم'"),

    # Start/Stop button
    ("'START BOT'", "'بدء البوت'"),
    ("'STOP BOT'", "'إيقاف البوت'"),

    # Tests counter
    ("'Tests: \\${ind.tests} | W: \\${ind.wins} L: \\${ind.losses}'",
     "'اختبارات: \\${ind.tests} | ف: \\${ind.wins} خ: \\${ind.losses}'"),
]

applied = 0
not_found = []

for old, new in repl:
    if old in src:
        src = src.replace(old, new)
        applied += 1
    else:
        not_found.append(old[:50])

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print(f"✅ Applied: {applied} / {len(repl)} replacements")
if not_found:
    print("\n⚠️ Not found (may already be translated or different format):")
    for nf in not_found:
        print(f"  - {nf}")
