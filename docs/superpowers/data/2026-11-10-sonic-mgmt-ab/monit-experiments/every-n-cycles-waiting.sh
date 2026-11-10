set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq monit >/dev/null
cat > /etc/monit/monitrc <<'RC'
set daemon 2
set httpd unixsocket /var/run/monit.sock allow localhost
check program prog with path "/bin/true" every 10 cycles
    if status != 0 then alert
RC
chmod 600 /etc/monit/monitrc
monit -c /etc/monit/monitrc
echo "monit $(monit -V | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
for i in $(seq 1 14); do sleep 2; printf "t=%2ds %s\n" $((i*2)) "$(monit -c /etc/monit/monitrc status prog 2>/dev/null | grep -E '^\s+status' | tr -s ' ' | xargs)"; done
