#!/bin/bash
# Patch dpkg's field_parse_maintainer to tolerate Maintainer field formats that
# resolute dpkg 1.23.7 rejects but trixie accepted:
#   1. comma-separated multiple Maintainers ('A <a@x>, B <b@y>') -> take first
#   2. square-bracket email ('Neil McKee [neil@x]') -> convert to <email>
# Upstream Debian policy says multiple maintainers go in Uploaders, and
# brackets are non-standard, but several SONiC upstream control files use them.
# Single source of truth covers all packages (rasdaemon, hsflowd, etc.) without
# per-package sed in Makefiles.
set -e
F=/usr/share/perl5/Dpkg/Control/FieldsCore.pm
grep -q "cannot parse %s field value" "$F"
python3 - <<'PY'
p = "/usr/share/perl5/Dpkg/Control/FieldsCore.pm"
t = open(p).read()
old = """    require Dpkg::Email::Address;
    eval {
        return Dpkg::Email::Address->new($maint);
    } or do {
        error(g_('cannot parse %s field value "%s"'),
              'Maintainer', $maint);
    };"""
new = """    require Dpkg::Email::Address;
    # resolute: tolerate formats trixie accepted. Try the raw value first;
    # on failure, retry with fallbacks (multi-maintainer -> first; square
    # brackets -> angle brackets) and warn, instead of erroring.
    my $parsed = eval { Dpkg::Email::Address->new($maint) };
    if (!$parsed) {
        my $fixed = $maint;
        $fixed =~ s/\\[([^\\]]+)\]/<$1>/;          # [email] -> <email>
        $fixed =~ s/,.*$// if $fixed =~ /,/;        # multi -> first
        $fixed =~ s/\\s+$//;
        $parsed = eval { Dpkg::Email::Address->new($fixed) };
        warning(g_('non-standard %s field value "%s"; using "%s"'),
                'Maintainer', $maint, $fixed) if $parsed;
    }
    return $parsed if $parsed;
    error(g_('cannot parse %s field value "%s"'),
          'Maintainer', $maint);"""
assert old in t, "field_parse_maintainer block not found"
t = t.replace(old, new)
open(p, "w").write(t)
print("patched Dpkg::Control::FieldsCore.pm: tolerate multi-Maintainer + brackets")
PY