#!/bin/bash
# Does the arm64 cEOS run natively? Boot one, check the CLI, an interface and a BGP session.
set -u
T=/srv/share/cEOSarm-lab-4.35.7.2M.tar
docker image inspect ceosarm:4.35.7.2M >/dev/null 2>&1 || docker import $T ceosarm:4.35.7.2M
docker rm -f ceos-a ceos-b >/dev/null 2>&1
docker network rm ceos-link >/dev/null 2>&1
docker network create --internal ceos-link >/dev/null
envs="-e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker -e MAPETH0=1 -e MGMT_INTF=eth0"
for n in a b; do
    docker create --name ceos-$n --privileged $envs ceosarm:4.35.7.2M /sbin/init \
        systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 \
        systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=docker >/dev/null
    docker network connect ceos-link ceos-$n
    docker start ceos-$n >/dev/null
done
t0=$(date +%s)
for i in $(seq 1 120); do
    sleep 10
    ok=0; for n in a b; do docker exec ceos-$n Cli -p 15 -c "show version" 2>/dev/null | grep -q "cEOS" && ok=$((ok+1)); done
    [ $ok = 2 ] && { echo "CLI up on both after $(( $(date +%s) - t0 )) s"; break; }
done
[ $ok = 2 ] || { echo "CLI not up after 20 min"; docker logs ceos-a 2>&1 | tail -20; exit 1; }
docker exec ceos-a Cli -p 15 -c "show version" | head -8
cfg() { docker exec ceos-$1 Cli -p 15 -c "configure
interface Ethernet1
no switchport
ip address $2/24
router bgp $3
neighbor $4 remote-as $5
end"; }
cfg a 10.9.0.1 65001 10.9.0.2 65002; cfg b 10.9.0.2 65002 10.9.0.1 65001
for i in $(seq 1 30); do sleep 10
    docker exec ceos-a Cli -p 15 -c "show ip bgp summary" | grep -q "10.9.0.2.*Estab" && { echo "BGP Established after $((i*10)) s more"; break; }
done
docker exec ceos-a Cli -p 15 -c "show ip bgp summary" | tail -3
docker exec ceos-a Cli -p 15 -c "ping 10.9.0.2 repeat 3" | tail -3
docker stats --no-stream ceos-a ceos-b
