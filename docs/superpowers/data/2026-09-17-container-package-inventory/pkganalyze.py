import json, glob, os, re, urllib.parse
OUT='/tmp/pkgscan-out'; DEBDIR='/home/sheldon-qi/sonic-buildimage-resolute/target/debs/resolute'
imgs={os.path.basename(f)[:-5]:json.load(open(f)) for f in glob.glob(f'{OUT}/*.json')}
VS=set("""docker-bmp-watchdog docker-dash-engine docker-dash-ha docker-database docker-dhcp-relay docker-eventd docker-fpm-frr docker-gbsyncd-vs docker-gnmi-sidecar docker-gnmi-watchdog docker-lldp docker-macsec docker-mux docker-nat docker-orchagent docker-platform-monitor docker-restapi-sidecar docker-router-advertiser docker-sflow docker-snmp docker-sonic-bmp docker-sonic-gnmi docker-sonic-mgmt-framework docker-sonic-otel docker-syncd-vs docker-sysmgr docker-teamd""".split())
BCM=set("""docker-bmp-watchdog docker-dash-ha docker-database docker-dhcp-relay docker-eventd docker-fpm-frr docker-gbsyncd-agera2 docker-gbsyncd-broncos docker-gbsyncd-credo docker-gnmi-sidecar docker-gnmi-watchdog docker-lldp docker-macsec docker-mux docker-nat docker-orchagent docker-platform-monitor docker-restapi-sidecar docker-router-advertiser docker-sflow docker-snmp docker-sonic-bmp docker-sonic-gnmi docker-sonic-mgmt-framework docker-sonic-otel docker-syncd-brcm docker-sysmgr docker-teamd""".split())
# self-built: name -> set(version-without-epoch)
self_built={}
for f in glob.glob(f'{DEBDIR}/*.deb'):
    n,v,_=os.path.basename(f)[:-4].split('_',2)
    self_built.setdefault(n,set()).add(urllib.parse.unquote(v).split(':',1)[-1])
def noepoch(v): return v.split(':',1)[-1]
def tag(name,ver):
    if name in self_built:
        return 'SELF' if noepoch(ver) in self_built[name] else 'STOCK(name-collides-with-self-built)'
    return 'STOCK'
def debset(i): return set(imgs[i]['debs'])
BASE,CFG,SWSS='docker-base-resolute','docker-config-engine-resolute','docker-swss-layer-resolute'
def parent(i):
    if i==BASE: return None
    if i==CFG: return BASE
    if i==SWSS: return CFG
    s=debset(i)
    if debset(SWSS)<=s: return SWSS
    if debset(CFG)<=s: return CFG
    if debset(BASE)<=s: return BASE
    return 'EXTERNAL'
def size_mb(i,names=None):
    d=imgs[i]['debs']; names=names if names is not None else d
    return sum(int(d[n]['Installed-Size'] or 0) for n in names)/1024
def pyclass(p): return 'pip' if p.startswith('usr/local/') else 'deb'
def pyname(p): return os.path.basename(p)
rows=[]; L=[]
L.append('# SONiC resolute 容器包清单 / Container package inventory (vs + broadcom)\n')
L.append(f'Generated 2026-09-17 from `sonic-buildimage-resolute/target/docker-*.gz` (34 images) by streaming `var/lib/dpkg/status` + python `*.dist-info` out of the OCI layers. No image was loaded or run.\n')
L.append('Tags: **SELF** = built from source in this repo (`target/debs/resolute/`), **STOCK** = Ubuntu 26.04 archive package (chisel-releases slice candidate). Python: `pip` = installed under `/usr/local` from a wheel, `deb` = shipped by a Debian package.\n')
L.append('## 1. Summary\n')
L.append('| image | vs | bcm | parent | debs | +over parent | SELF | STOCK | inst. size MB | py dists (pip/deb) |')
L.append('|---|:-:|:-:|---|--:|--:|--:|--:|--:|---|')
order=[BASE,CFG,SWSS]+sorted(i for i in imgs if i not in (BASE,CFG,SWSS))
for i in order:
    p=parent(i); d=imgs[i]['debs']
    added=set(d)-(debset(p) if p and p!='EXTERNAL' else set())
    selfc=sum(1 for n in d if tag(n,d[n]['Version'])=='SELF')
    py=imgs[i]['python']; pip=sum(1 for x in py if pyclass(x)=='pip')
    L.append(f"| {i} | {'✓' if i in VS else ''} | {'✓' if i in BCM else ''} | {p or '-'} | {len(d)} | {len(added)} | {selfc} | {len(d)-selfc} | {size_mb(i):.0f} | {len(py)} ({pip}/{len(py)-pip}) |")
def dump_debs(i, names, hdr):
    d=imgs[i]['debs']
    L.append(f'\n{hdr}\n'); L.append('| package | version | tag | prio/section | KB |'); L.append('|---|---|---|---|--:|')
    for n in sorted(names, key=lambda n:(tag(n,d[n]['Version'])!='SELF', n)):
        v=d[n]; L.append(f"| {n} | {v['Version']} | {tag(n,v['Version'])} | {v['Priority']}/{v['Section']} | {v['Installed-Size']} |")
def dump_py(i, names, hdr):
    if not names: return
    L.append(f'\n{hdr}\n'); L.append('| dist | how |'); L.append('|---|---|')
    for x in sorted(names, key=pyname): L.append(f'| {pyname(x)} | {pyclass(x)} `{os.path.dirname(x)}` |')
L.append('\n## 2. Layer 0: docker-base-resolute (inherited by every SONiC container except dash-engine)\n')
dump_debs(BASE, debset(BASE), f'### debs ({len(debset(BASE))}, {size_mb(BASE):.0f} MB)')
dump_py(BASE, imgs[BASE]['python'], '### python dists')
for i,p in ((CFG,BASE),(SWSS,CFG)):
    L.append(f'\n## Layer: {i} (parent {p})\n')
    add=debset(i)-debset(p); rem=debset(p)-debset(i)
    dump_debs(i, add, f'### debs added ({len(add)}, {size_mb(i,add):.0f} MB)')
    if rem: L.append(f'\nremoved vs parent: {", ".join(sorted(rem))}')
    dump_py(i, set(imgs[i]['python'])-set(imgs[p]['python']), '### python dists added')
L.append('\n## 3. Leaf containers: delta over parent\n')
for i in order:
    if i in (BASE,CFG,SWSS): continue
    p=parent(i)
    plat=' / '.join(x for x,s in (('vs',VS),('bcm',BCM)) if i in s)
    L.append(f'\n### {i}  [{plat}]  parent={p}\n')
    if p=='EXTERNAL':
        d=imgs[i]['debs']; L.append(f"External base (not docker-base-resolute): libc6 {d.get('libc6',{}).get('Version','?')}, {len(d)} debs, {size_mb(i):.0f} MB. Full list:")
        dump_debs(i, debset(i), '#### debs'); dump_py(i, imgs[i]['python'], '#### python dists'); continue
    add=debset(i)-debset(p); rem=debset(p)-debset(i)
    dump_debs(i, add, f'#### debs added ({len(add)}, {size_mb(i,add):.0f} MB)')
    if rem: L.append(f'\nremoved vs parent: {", ".join(sorted(rem))}')
    dump_py(i, set(imgs[i]['python'])-set(imgs[p]['python']), '#### python dists added')
# union of stock packages across all SONiC-base images (for chisel slice scoping)
L.append('\n## 4. Union of STOCK Ubuntu packages across all vs+bcm containers (chisel slice scope)\n')
union={}
for i in VS|BCM:
    if parent(i)=='EXTERNAL': continue
    for n,v in imgs[i]['debs'].items():
        if tag(n,v['Version'])!='SELF': union.setdefault(n,set()).add(i)
L.append(f'{len(union)} distinct stock packages.\n'); L.append('| package | used by N images | only in |'); L.append('|---|--:|---|')
for n in sorted(union, key=lambda n:(-len(union[n]),n)):
    s=union[n]; L.append(f"| {n} | {len(s)} | {'' if len(s)>=25 else ', '.join(sorted(s))} |")
L.append('\n## 5. Union of SELF-built debs across all vs+bcm containers\n')
selfu={}
for i in VS|BCM:
    for n,v in imgs[i]['debs'].items():
        if tag(n,v['Version'])=='SELF': selfu.setdefault(n,set()).add(i)
L.append('| package | used by |'); L.append('|---|---|')
for n in sorted(selfu): L.append(f"| {n} | {', '.join(sorted(selfu[n]))} |")
open('/tmp/pkgscan-out/REPORT.md','w').write('\n'.join(L)+'\n')
print('wrote REPORT.md', len(L),'lines'); print('external:', [i for i in imgs if parent(i)=='EXTERNAL'])
print('parents:', {i:parent(i) for i in order if i not in (BASE,CFG,SWSS)})
