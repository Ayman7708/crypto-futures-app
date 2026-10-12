with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Add Search tab before Settings (Arabic version)
old_tabs = "Tab(text: 'المعتمدة'), Tab(text: 'الإعدادات'),"
new_tabs = "Tab(text: 'المعتمدة'), Tab(text: 'البحث'), Tab(text: 'الإعدادات'),"

fixed = False
if old_tabs in src:
    src = src.replace(old_tabs, new_tabs, 1)
    fixed = True
    print("✅ Arabic tabs: added البحث before الإعدادات")
else:
    print("❌ Arabic pattern not found. Searching alternatives...")
    import re
    # Try to find Arabic tabs
    for i, line in enumerate(src.split('\n'), 1):
        if 'Tab(text:' in line and 'إعدادات' in line:
            print(f"  Line {i}: {line.strip()}")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

search_tab_ar = "Tab(text: 'البحث')" in final
settings_tab_ar = "Tab(text: 'الإعدادات')" in final
search_screen = "SearchScreen()" in final

print()
print(f"✅ Tab البحث موجود: {search_tab_ar}")
print(f"✅ Tab الإعدادات موجود: {settings_tab_ar}")
print(f"✅ SearchScreen في TabBarView: {search_screen}")

# Count tabs
import re
tab_block = re.search(r"tabs: const \[(.*?)\],", final, re.DOTALL)
if tab_block:
    count = tab_block.group(1).count("Tab(text:")
    print(f"📊 عدد التبويبات: {count}")
