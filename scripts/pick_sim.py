import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(x) for x in runtime.split("iOS-")[-1].split("-") if x.isdigit())
    for d in devs:
        if d["name"].startswith("iPhone") and "Pro" in d["name"] and "Max" not in d["name"]:
            key = (ver, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"])
if best is None:
    for runtime, devs in data.items():
        for d in devs:
            if "iOS" in runtime and d["name"].startswith("iPhone"):
                best = (None, d["udid"])
print(best[1])
