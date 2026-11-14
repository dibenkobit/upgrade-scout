"""Prints the ConsumesSpec blocks of the UI presets with the consumable names resolved to item ids.

Usage: python -I ui_consumables.py <clone> <spec dir under ui/specs>...
"""
import re
import sys

clone = sys.argv[1]
ids = dict(
    re.findall(
        r"export const (\w+) = \{ id: (\d+) \};",
        open(clone + "/ui/features/settings/model/consumables_auto_gen.ts", encoding="utf-8").read(),
    )
)
for spec in sys.argv[2:]:
    text = open(f"{clone}/ui/specs/{spec}/presets.ts", encoding="utf-8").read()
    for match in re.finditer(r"export const (\w*Consum\w*) = ConsumesSpec\.create\(\{(.*?)\}\);", text, flags=re.S):
        body = re.sub(r"Consumables\.(\w+)\.id", lambda m: f"{ids.get(m.group(1), '?')} /*{m.group(1)}*/", match.group(2))
        body = " ".join(body.split())
        print(f"{spec}: {match.group(1)} = {body}")
