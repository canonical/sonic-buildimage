#!/usr/bin/env bash
#Generate supervisord.conf based on device metadata

cp -r ${SNAP}/etc/supervisor/ ${SNAP_DATA}/etc/

sonic-cfggen -d -a "{\"namespace_id\":\"$NAMESPACE_ID\"}" -t ${SNAP}/usr/share/sonic/templates/supervisord.conf.j2 > /etc/supervisor/conf.d/supervisord.conf
exec ${SNAP}/usr/local/bin/supervisord
