"""Assign every rock/df call-outcome difference of the main run to a cause; print counts per cause.

usage: python3 -I buckets.py <tf dir>
"""
import importlib.util
import sys
from collections import Counter, defaultdict
from pathlib import Path

T = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("analyze", T / "analyze.py")
an = importlib.util.module_from_spec(spec); spec.loader.exec_module(an)
CAUSES = [
    ("gnmi helpers (supervisorctl; pebble shuts the container down)", ("gnmi.", "platform_tests.test_reboot", "minigraph.")),
    ("snmp subagent check (supervisorctl)", ("snmp.", "cacl.")),
    ("dhcp_relay state and pid (supervisorctl)", ("dhcp_relay.test_dhcp_relay", "generic_config_updater.test_dhcp_relay")),
    ("telemetry event helpers (supervisorctl, python)", ("telemetry.",)),
    ("arp_update / rsyslogd control (supervisorctl)", ("arp.", "crm.", "dualtor.", "syslog.test_syslog_rate_limit", "pc.")),
    ("like-bgp container entrypoint", ("bgp.",)),
    ("bmp state (supervisorctl)", ("bmp.",)),
    ("radvd SIGHUP (supervisorctl)", ("radv.",)),
    ("pmon / lldp control (supervisorctl)", ("platform_tests.test_platform_info", "monit.")),
    ("rock product: on-failure shutdown vs auto_restart", ("process_monitoring.",)),
    ("not a difference: randomised parameters", ("hash.",)),
    ("not a difference: testbed loop device busy (df)", ("syslog.test_logrotate",)),
]
df, rock = an.merged(T / "main", "df"), an.merged(T / "main", "rock")
counts, files = Counter(), defaultdict(set)
for key in sorted(set(df) | set(rock)):
    a, b = df.get(key, ("absent",)), rock.get(key, ("absent",))
    if a[0] == b[0]:
        continue
    module = key.split("::")[0][len("tests."):]
    cause = next((c for c, prefixes in CAUSES if module.startswith(prefixes)), "UNASSIGNED " + module)
    counts[cause] += 1
    files[cause].add(module.split(".Test")[0])
for cause, n in counts.most_common():
    print("{:4} cases {:3} files  {}".format(n, len(files[cause]), cause))
print(sum(counts.values()), "cases,", len(set().union(*files.values())), "files")
