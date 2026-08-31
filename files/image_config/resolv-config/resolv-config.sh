#!/bin/bash
#
# SONiC owns /etc/resolv.conf as a regular file.
#
# systemd-resolved.service(8) documents four ways /etc/resolv.conf can be
# handled; the last one is "managed by other packages", where resolved reads the
# file as configuration instead of generating it. That is the mode used here, so
# the glibc resolver keeps reading exactly what SONiC renders — including the
# search/ndots/timeout/attempts of DNS_OPTIONS, which resolved cannot express
# (its stub resolver does not implement ndots at all).
#
# Static configuration wins over DHCP: while it is in effect a marker is left for
# the dhclient hook, which then leaves /etc/resolv.conf alone.

RESOLV_CONF=/etc/resolv.conf
RESOLV_CONF_HEAD=/usr/share/sonic/templates/resolv.conf.head
RESOLV_CONF_TEMPLATE=/usr/share/sonic/templates/resolv.conf.j2
STATIC_MARKER=/run/sonic-resolv-static
UPDATE_CONTAINERS=/usr/bin/update-containers

render_static()
{
    local tmp
    tmp=$(mktemp)
    cat ${RESOLV_CONF_HEAD} > ${tmp}
    sonic-cfggen -d -t ${RESOLV_CONF_TEMPLATE} >> ${tmp}
    # Earlier images symlinked /etc/resolv.conf into the resolvconf run
    # directory; replace whatever is there with a regular file.
    rm -f ${RESOLV_CONF}
    install -m 644 ${tmp} ${RESOLV_CONF}
    rm -f ${tmp}
    touch ${STATIC_MARKER}
}

start()
{
    has_static_mgmt_ip=false
    mgmt_ip_cfg=$(redis-dump -d 4 -k "MGMT_INTERFACE|eth0|*" -y)
    if [[ $? -eq 0 && ${mgmt_ip_cfg} != "{}" ]]; then
        has_static_mgmt_ip=true
    fi

    has_static_dns=false
    dns_cfg=$(redis-dump -d 4 -k "DNS_NAMESERVER*" -y)
    if [[ $? -eq 0 && ${dns_cfg} != "{}" ]]; then
        has_static_dns=true
    fi

    if [[ ${has_static_mgmt_ip} == true || ${has_static_dns} == true ]]; then
        render_static
    else
        # Dynamic configuration: the dhclient hook renders /etc/resolv.conf from
        # the lease. Reset the file when static configuration has just been
        # removed — its nameservers are stale, and nothing else would clear them
        # until a lease event happens to arrive — but leave a file the hook has
        # already written alone, and make sure one exists before the first lease.
        if [[ -e ${STATIC_MARKER} || -L ${RESOLV_CONF} || ! -e ${RESOLV_CONF} ]]; then
            rm -f ${RESOLV_CONF}
            install -m 644 ${RESOLV_CONF_HEAD} ${RESOLV_CONF}
        fi
        rm -f ${STATIC_MARKER}
    fi

    ${UPDATE_CONTAINERS}
}

case $1 in
    start)
        start
        ;;
    *)
        echo "Usage: $0 {start}"
        exit 2
        ;;
esac
