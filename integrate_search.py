with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Import
if "import 'search_screen.dart';" not in src:
    src = src.replace(
        "import 'master_signal.dart';",
        "import 'master_signal.dart';\nimport 'search_screen.dart';"
    )
checks.append(('import', "import 'search_screen.dart';" in src))

# 2) TabController length 7 -> 8
src = src.replace("TabController(length: 7,", "TabController(length: 8,")
checks.append(('tabs 8', 'TabController(length: 8,' in src))

# 3) Add tab in TabBar
old_tabs = """            Tab(text: 'Main'), Tab(text: 'Analysis'),
            Tab(text: 'History'), Tab(text: 'Backtest'), Tab(text: 'Testing'),
            Tab(text: 'Approved'), Tab(text: 'Settings'),"""
new_tabs = """            Tab(text: 'Main'), Tab(text: 'Analysis'),
            Tab(text: 'History'), Tab(text: 'Backtest'), Tab(text: 'Testing'),
            Tab(text: 'Approved'), Tab(text: 'Search'), Tab(text: 'Settings'),"""
if old_tabs in src:
    src = src.replace(old_tabs, new_tabs)
    checks.append(('tabbar', "Tab(text: 'Search')" in src))
else:
    checks.append(('tabbar', False))

# 4) Add SearchScreen to TabBarView
old_children = """          _buildDashboard(), _buildAnalytics(), _buildTrades(),
          _buildBacktest(), _buildTestingIndicators(), _buildApprovedIndicators(),
          _buildSettings(),"""
new_children = """          _buildDashboard(), _buildAnalytics(), _buildTrades(),
          _buildBacktest(), _buildTestingIndicators(), _buildApprovedIndicators(),
          const SearchScreen(), _buildSettings(),"""
if old_children in src:
    src = src.replace(old_children, new_children)
    checks.append(('tabview', 'const SearchScreen()' in src))
else:
    checks.append(('tabview', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Integrate Search ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('========================')
