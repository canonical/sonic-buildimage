#!/bin/bash
# Add rtnl_route_get_nh_id / set_nh_id aliases to libnl 3.12.0.
#
# libnl 3.12.0 natively supports RTA_NH_ID via rtnl_route_get_nhid/set_nhid
# (field rt_nhid, attr ROUTE_ATTR_NHID). SONiC's swss fpmsyncd calls
# rtnl_route_get_nh_id (with underscore), the naming from the old SONiC 0003
# patch for libnl 3.7.0. Add thin aliases so swss builds unchanged.
#
# Run from the libnl3-3.12.0 source root.

set -e

# 1. Public header declarations (after the native nhid declarations).
sed -i '/^extern uint32_t\trtnl_route_get_nhid/a\
extern uint32_t\trtnl_route_get_nh_id(struct rtnl_route *);' include/netlink/route/route.h
sed -i '/^extern void\trtnl_route_set_nhid/a\
extern void\trtnl_route_set_nh_id(struct rtnl_route *, uint32_t);' include/netlink/route/route.h

# 2. Alias function definitions appended to route_obj.c (forward-declared
#    by the header above, so placement at end-of-file is fine).
cat >> lib/route/route_obj.c <<'EOF'

void rtnl_route_set_nh_id(struct rtnl_route *route, uint32_t nhid)
{
	rtnl_route_set_nhid(route, nhid);
}

uint32_t rtnl_route_get_nh_id(struct rtnl_route *route)
{
	return rtnl_route_get_nhid(route);
}
EOF

# 3. Linker version-script: export the aliases under the same version node
#    as the native nhid symbols (libnl_3_9 in libnl-route-3.sym).
awk '
/^\trtnl_route_get_nhid;$/ { print; print "\trtnl_route_get_nh_id;"; next }
/^\trtnl_route_set_nhid;$/ { print; print "\trtnl_route_set_nh_id;"; next }
{ print }
' libnl-route-3.sym > libnl-route-3.sym.tmp && mv libnl-route-3.sym.tmp libnl-route-3.sym

# 4. dpkg symbols file metadata (no leading tab here).
awk '
/^rtnl_route_get_nhid;$/ { print; print "rtnl_route_get_nh_id;"; next }
/^rtnl_route_set_nhid;$/ { print; print "rtnl_route_set_nh_id;"; next }
{ print }
' debian/libnl-route-3-200.symbols > debian/libnl-route-3-200.symbols.tmp && \
   mv debian/libnl-route-3-200.symbols.tmp debian/libnl-route-3-200.symbols
