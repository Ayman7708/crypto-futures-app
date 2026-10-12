import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Find the tabs list inside TabBar and add Search tab before Settings
# Pattern: `Tab(text: 'Settings')` — insert Search tab before it
old_tab_patterns = [
    "Tab(text: 'Settings'),\n          ],",
    "Tab(text: 'Settings'),\n            ],",
    "Tab(text: 'Settings'),\n        ],",
]
fixed = False
for pat in old_tab_patterns:
    if pat in src:
        new_pat = pat.replace("Tab(text: 'Settings'),", "Tab(text: 'Search'),\n            Tab(text: 'Settings'),")
        src = src.replace(pat, new_pat, 1)
        fixed = True
        break

# Alternative: search for the full tabs block
if not fixed:
    m = re.search(r"tabs: const \[(.*?)\],", src, re.DOTALL)
    if m:
        block = m.group(1)
        if "Tab(text: 'Search')" not in block:
            new_block = block.rstrip()
            # Insert Search before Settings
            new_block = new_block.replace("Tab(text: 'Settings')", "Tab(text: 'Search'),\n            Tab(text: 'Settings')")
            src = src.replace(m.group(0), f"tabs: const [{new_block}],", 1)
            fixed = True

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

search_tab = "Tab(text: 'Search')" in final
search_view = "SearchScreen()" in final

print(f'✅ Search tab in TabBar: {search_tab}')
print(f'✅ SearchScreen in TabBarView: {search_view}')

if not search_tab:
    print('\n⚠️ لم يُضف التاب. محتوى TabBar الحالي:')
    m = re.search(r"tabs: const \[.*?\],", final, re.DOTALL)
    if m:
        for line in m.group(0).split('\n'):
            print(f'  {line}')
