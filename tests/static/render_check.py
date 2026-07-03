#!/usr/bin/env python3
"""render_check.py — render the Mihomo config template with sample values and
verify the result is valid YAML with the expected security-critical defaults.
Also validates all subscription fixtures parse as YAML.
Exit non-zero on any failure. Used by tests/static/run_static.sh."""
import glob
import re
import sys

try:
    import yaml
except ImportError:
    print("  SKIP: pyyaml not installed")
    sys.exit(0)

ROOT = __import__("os").path.dirname(__file__) + "/../.."
TMPL = ROOT + "/files/etc/submihomo/templates/base.yaml.tmpl"

FAIL = 0


def fail(msg):
    global FAIL
    print("  FAIL:", msg)
    FAIL = 1


# ── Render template (loopback default: allow_lan_access=0) ──────────────────
tmpl = open(TMPL).read()
subs = {
    "MIXED_PORT": "7890", "TPROXY_PORT": "7891", "CTRL_PORT": "9090",
    "CTRL_BIND": "127.0.0.1", "LOG_LEVEL": "warning", "ALLOW_LAN": "false",
    "CTRL_SECRET": "testsecret",
    "DASHBOARD_DIR": "/usr/share/submihomo/dashboard",
}
for k, v in subs.items():
    tmpl = tmpl.replace("{{%s}}" % k, v)
dns_block = """dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/15
  fake-ip-filter:
    - "*.lan"
  nameserver:
    - https://1.1.1.1/dns-query"""
tmpl = tmpl.replace("{{DNS_SECTION}}", dns_block)

try:
    doc = yaml.safe_load(tmpl)
    print("  OK: rendered template parses as YAML")
    if doc.get("external-controller") != "127.0.0.1:9090":
        fail("external-controller should default to 127.0.0.1:9090, got %r"
             % doc.get("external-controller"))
    else:
        print("  OK: external-controller defaults to loopback (127.0.0.1:9090)")
    if doc.get("tproxy-port") != 7891:
        fail("tproxy-port wrong: %r" % doc.get("tproxy-port"))
    if doc.get("ipv6") is not False:
        fail("ipv6 must be false, got %r" % doc.get("ipv6"))
    if doc.get("dns", {}).get("enhanced-mode") != "fake-ip":
        fail("dns.enhanced-mode wrong")
except Exception as e:
    fail("template YAML parse: %s" % e)

# Only the header-comment token may remain
leftover = [t for t in re.findall(r"{{.*?}}", tmpl) if t != "{{PLACEHOLDER}}"]
if leftover:
    fail("unsubstituted tokens: %s" % leftover)
else:
    print("  OK: no stray substitution tokens")

# ── Render with allow_lan_access=1 → 0.0.0.0 ────────────────────────────────
tmpl2 = open(TMPL).read()
subs["CTRL_BIND"] = "0.0.0.0"
subs["ALLOW_LAN"] = "true"
for k, v in subs.items():
    tmpl2 = tmpl2.replace("{{%s}}" % k, v)
tmpl2 = tmpl2.replace("{{DNS_SECTION}}", dns_block)
try:
    doc2 = yaml.safe_load(tmpl2)
    if doc2.get("external-controller") != "0.0.0.0:9090":
        fail("LAN mode should bind 0.0.0.0, got %r" % doc2.get("external-controller"))
    else:
        print("  OK: LAN mode binds 0.0.0.0:9090")
except Exception as e:
    fail("LAN-mode template parse: %s" % e)

# ── Fixtures ────────────────────────────────────────────────────────────────
for f in sorted(glob.glob(ROOT + "/tests/unit/fixtures/*.yaml")):
    try:
        yaml.safe_load(open(f))
        print("  OK: fixture %s" % f.split("/")[-1])
    except Exception as e:
        fail("fixture %s: %s" % (f, e))

sys.exit(FAIL)
