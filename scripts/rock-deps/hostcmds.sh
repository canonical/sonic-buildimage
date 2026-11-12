#!/bin/bash
# Trigger for collect.sh: run, on the switch, the host-side commands that reach into the batch-1 containers
# (docker_image_ctl.j2, show, update-containers, debug_info, config syslog, fast-reboot; see host-callers.sh).
# Usage (on the switch): sudo bash hostcmds.sh     Needs: SONiC host with database/radv/eventd/mgmt-framework running.
set -x
ctrs=(database radv eventd mgmt-framework)

show services >/dev/null 2>&1
update-containers >/dev/null 2>&1

for c in "${ctrs[@]}"; do
    docker exec -i "$c" ps aux >/dev/null                     # show services
    timeout 5s docker exec "$c" echo success >/dev/null       # fast-reboot
    docker exec -i "$c" pebble services >/dev/null            # utilities_common/cli.py
    docker exec -i "$c" pgrep -x -c pebble >/dev/null         # docker_image_ctl.j2 readiness
    docker exec -i "$c" pebble signal HUP rsyslogd >/dev/null # config syslog
    docker exec -t "$c" bash -c "cat /etc/resolv.conf >/dev/null"
    docker exec "$c" touch /tmp/rockdeps-probe                # generate_dump
    docker exec "$c" mkdir -p /tmp/rockdeps-probe.d
    docker exec -i "$c" rm -rf /tmp/rockdeps-probe /tmp/rockdeps-probe.d
    docker exec -i "$c" kill -0 1                             # config syslog (kill -s SIGHUP <pid>)
done

docker exec -i database sonic-db-cli PING >/dev/null
docker exec -i database sysctl -n net.ipv4.ip_forward >/dev/null
docker exec -i database sed --version >/dev/null
docker exec -i database ip addr show eth0 >/dev/null
docker exec -i database redis-cli -n 1 hgetall VIDTORID >/dev/null
docker exec -i database redis-dump -H 127.0.0.1 -p 6379 -d 4 -y >/dev/null
docker exec -i eventd ls /etc/rsyslog.d/rsyslog_plugin_conf >/dev/null
exit 0
