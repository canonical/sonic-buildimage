set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq monit >/dev/null
cat > /etc/monit/monitrc <<'RC'
set daemon 2
set httpd unixsocket /var/run/monit.sock allow localhost
check program p with path "/x/prog.sh"
    if status == 3 for 2 times within 20 cycles then exec "/usr/bin/touch /tmp/restarted"
RC
chmod 600 /etc/monit/monitrc
monit -c /etc/monit/monitrc
echo "monit $(monit -V | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
sleep 8
touch /tmp/flag; t0=$(date +%s.%N)
until monit -c /etc/monit/monitrc status p 2>/dev/null | grep -q "last exit value *3"; do sleep 0.2; done
t1=$(date +%s.%N); rm -f /tmp/flag
echo "failure seen after $(echo "$t1 - $t0" | bc) s; flag removed"
sleep 10
[ -e /tmp/restarted ] && echo "RESULT: action fired (restart)" || echo "RESULT: no action"
