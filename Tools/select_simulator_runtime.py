"""Use the runtime matching the selected Xcode SDK, never an arbitrary latest OS."""
import json
import sys

sdk = tuple(sys.argv[1].split(".")[:2])
runtimes = json.load(sys.stdin)["runtimes"]
matches = [r for r in runtimes if r.get("isAvailable") and "iOS" in r["name"]
           and tuple(r["version"].split(".")[:2]) == sdk]
if not matches:
    raise SystemExit("No available iOS simulator matches Xcode SDK " + sys.argv[1])
print(matches[-1]["identifier"])
