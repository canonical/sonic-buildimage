import json, glob, os, subprocess, urllib.parse, collections
R='/home/sheldon-qi/chisel-releases'; OUT='/tmp/pkgscan-out'
ARCH=json.load(open('/tmp/ubuntu-idx/resolute-amd64.json'))
def slices(branch):
    out=subprocess.run(['git','-C',R,'ls-tree','--name-only',f'origin/{branch}','slices/'],capture_output=True,text=True).stdout
    return {os.path.basename(l)[:-5] for l in out.split() if l.endswith('.yaml')}
S26,S2510,S2404=slices('ubuntu-26.04'),slices('ubuntu-25.10'),slices('ubuntu-24.04')
imgs={os.path.basename(f)[:-5]:json.load(open(f)) for f in glob.glob(f'{OUT}/*.json')}
sb={}
for f in glob.glob('/home/sheldon-qi/sonic-buildimage-resolute/target/debs/resolute/*.deb'):
    n,v,_=os.path.basename(f)[:-4].split('_',2); sb.setdefault(n,set()).add(urllib.parse.unquote(v).split(':')[-1])
def is_self(n,v): return n in sb and v.split(':')[-1] in sb[n]
VS=set("docker-bmp-watchdog docker-dash-engine docker-dash-ha docker-database docker-dhcp-relay docker-eventd docker-fpm-frr docker-gbsyncd-vs docker-gnmi-sidecar docker-gnmi-watchdog docker-lldp docker-macsec docker-mux docker-nat docker-orchagent docker-platform-monitor docker-restapi-sidecar docker-router-advertiser docker-sflow docker-snmp docker-sonic-bmp docker-sonic-gnmi docker-sonic-mgmt-framework docker-sonic-otel docker-syncd-vs docker-sysmgr docker-teamd".split())
BCM=set("docker-bmp-watchdog docker-dash-ha docker-database docker-dhcp-relay docker-eventd docker-fpm-frr docker-gbsyncd-agera2 docker-gbsyncd-broncos docker-gbsyncd-credo docker-gnmi-sidecar docker-gnmi-watchdog docker-lldp docker-macsec docker-mux docker-nat docker-orchagent docker-platform-monitor docker-restapi-sidecar docker-router-advertiser docker-sflow docker-snmp docker-sonic-bmp docker-sonic-gnmi docker-sonic-mgmt-framework docker-sonic-otel docker-syncd-brcm docker-sysmgr docker-teamd".split())
B,C,W='docker-base-resolute','docker-config-engine-resolute','docker-swss-layer-resolute'
layer_of={}
for n in imgs[B]['debs']: layer_of[n]='base'
for n in imgs[C]['debs']: layer_of.setdefault(n,'config-engine')
for n in imgs[W]['debs']: layer_of.setdefault(n,'swss-layer')
pk={}
for i in (VS|BCM)-{'docker-dash-engine'}:
    for n,v in imgs[i]['debs'].items():
        e=pk.setdefault(n,{'v':v['Version'],'sec':v['Section'],'size':int(v['Installed-Size'] or 0),'imgs':set()}); e['imgs'].add(i)
def origin(n,v):
    if is_self(n,v): return 'SELF'
    if n not in ARCH: return 'THIRD-PARTY'
    return 'ARCHIVE' if v in ARCH[n] else 'ARCHIVE(ver-diff)'
BUILD_NAMES={'autoconf','automake','autotools-dev','m4','make','pkgconf','pkgconf-bin','libpkgconf7','pkg-config','thrift-compiler','rpcsvc-proto','xml-core','sgml-base','libtool','patch','linux-libc-dev','libc-dev-bin','libcrypt-dev','libc6-dev','protobuf-compiler','protobuf-compiler-grpc','libprotoc-dev','cpp','gcc','g++','build-essential','dpkg-dev','libisl23','libmpc3','libmpfr6'}
def cls(n,e):
    if n.endswith('-dev') or e['sec'] in ('libdevel','devel') or n in BUILD_NAMES or n.startswith(('cpp-','gcc-','g++-','llvm-','libclang','clang','binutils','libasan','libtsan','libubsan','liblsan','libhwasan','libgprofng','libobjc-','libgcc-','libstdc++-')): return 'build-only'
    if n in ('apt','apt-utils','dpkg','libapt-pkg7.0','debconf','ubuntu-keyring','gpgv','python3-pip','python3-setuptools','python3-wheel','python3-pkg-resources','ucf','libdebconfclient0'): return 'pkg-mgmt'
    if n.startswith(('perl','libperl')) or e['sec']=='perl': return 'perl'
    return 'runtime'
def status(n): return '26.04' if n in S26 else ('port<-25.10' if n in S2510 else ('port<-24.04' if n in S2404 else 'NEW'))
rows=[(n,e,origin(n,e['v']),status(n),cls(n,e),layer_of.get(n,'leaf')) for n,e in pk.items()]
oc=collections.Counter(r[2] for r in rows); print('origin:',dict(oc))
print('\nTHIRD-PARTY:', sorted((r[0],r[1]['v'],r[1]['size']//1024) for r in rows if r[2]=='THIRD-PARTY'))
print('\nARCHIVE(ver-diff):', sorted((r[0],r[1]['v'],ARCH[r[0]]) for r in rows if r[2]=='ARCHIVE(ver-diff)'))
print('\nport<-24.04:', sorted(r[0] for r in rows if r[3]=='port<-24.04'))
arch=[r for r in rows if r[2].startswith('ARCHIVE')]
print(f'\nARCHIVE pkgs {len(arch)}: coverage by class x status')
tab=collections.Counter((r[4],r[3]) for r in arch)
for c in ('runtime','perl','pkg-mgmt','build-only'):
    print(f"  {c:11s}", {st:tab[(c,st)] for st in ('26.04','port<-24.04','NEW')})
print('runtime ARCHIVE by layer x status')
tab2=collections.Counter((r[5],r[3]) for r in arch if r[4]=='runtime')
for l in ('base','config-engine','swss-layer','leaf'): print(f"  {l:14s}", {st:tab2[(l,st)] for st in ('26.04','port<-24.04','NEW')})
# ---- report
L=['# chisel-releases coverage of SONiC resolute container packages\n',
 f'Generated 2026-09-17. Sources: 30 SONiC-base containers (dash-engine excluded: external Ubuntu 20.04 image); Ubuntu resolute(+updates,+security) main+universe amd64 Packages index ({len(ARCH)} pkgs); chisel-releases `origin/ubuntu-26.04`@70d32b4 ({len(S26)} SDFs), 25.10 ({len(S2510)}), 24.04 ({len(S2404)}).\n',
 '## Origin of every deb found in the containers\n','| origin | count | meaning |','|---|--:|---|',
 f"| ARCHIVE | {oc['ARCHIVE']} | name+version present in Ubuntu resolute archive → chisel can cut it, given an SDF |",
 f"| ARCHIVE(ver-diff) | {oc['ARCHIVE(ver-diff)']} | name in archive but installed version differs (pinned/PPA) → SDF may apply, source must be checked |",
 f"| SELF | {oc['SELF']} | built from source in sonic-buildimage (`target/debs/resolute/`) → not in any chisel archive |",
 f"| THIRD-PARTY | {oc['THIRD-PARTY']} | downloaded binary deb (vendor SAI, otelcol) → not in any chisel archive |",
 '\n### THIRD-PARTY debs\n','| package | version | MB | containers |','|---|---|--:|---|']
for r in sorted([r for r in rows if r[2]=='THIRD-PARTY']): L.append(f"| {r[0]} | {r[1]['v']} | {r[1]['size']//1024} | {', '.join(sorted(r[1]['imgs']))} |")
L+=['\n### ARCHIVE(ver-diff)\n','| package | installed | archive has |','|---|---|---|']
for r in sorted([r for r in rows if r[2]=='ARCHIVE(ver-diff)']): L.append(f"| {r[0]} | {r[1]['v']} | {', '.join(ARCH[r[0]])} |")
L+=['\n## chisel-releases SDF coverage (ARCHIVE + ver-diff packages only)\n',
 'Status: **26.04** = SDF exists on ubuntu-26.04 · **port<-24.04** = only on 24.04 (forward-port = adaptation) · **NEW** = no SDF on 26.04/25.10/24.04. 25.10 adds nothing over 26.04 for our set.\n',
 'Class (heuristic): runtime · perl · pkg-mgmt (apt/dpkg/pip tooling; a chiselled rock normally drops these) · build-only (-dev, compilers, autotools; should never be in a runtime image).\n',
 '| class | 26.04 | port<-24.04 | NEW | total |','|---|--:|--:|--:|--:|']
for c in ('runtime','perl','pkg-mgmt','build-only'): L.append(f"| {c} | {tab[(c,'26.04')]} | {tab[(c,'port<-24.04')]} | {tab[(c,'NEW')]} | {sum(tab[(c,s)] for s in ('26.04','port<-24.04','NEW'))} |")
L+=['\n### runtime class, by layer\n','| layer | 26.04 | port<-24.04 | NEW |','|---|--:|--:|--:|']
for l in ('base','config-engine','swss-layer','leaf'): L.append(f"| {l} | {tab2[(l,'26.04')]} | {tab2[(l,'port<-24.04')]} | {tab2[(l,'NEW')]} |")
L+=['\n## Runtime ARCHIVE packages with no 26.04 SDF (the SDF-authoring backlog), sorted by #containers desc\n','| package | version | section | KB | layer | containers | status |','|---|---|---|--:|---|--:|---|']
for n,e,o,st,c,l in sorted([r for r in arch if r[3]!='26.04' and r[4]=='runtime'], key=lambda r:(-len(r[1]['imgs']),{'base':0,'config-engine':1,'swss-layer':2,'leaf':3}[r[5]],r[0])):
    L.append(f"| {n} | {e['v']} | {e['sec']} | {e['size']} | {l} | {len(e['imgs'])} | {st} |")
L+=['\n## Non-runtime ARCHIVE packages with no 26.04 SDF (expected to be dropped, not sliced)\n','| package | class | section | KB | layer | containers |','|---|---|---|--:|---|--:|']
for n,e,o,st,c,l in sorted([r for r in arch if r[3]!='26.04' and r[4]!='runtime'], key=lambda r:(r[4],-len(r[1]['imgs']),r[0])): L.append(f"| {n} | {c} | {e['sec']} | {e['size']} | {l} | {len(e['imgs'])} |")
L+=['\n## ARCHIVE packages already covered on 26.04\n','| package | class | layer | containers |','|---|---|---|--:|']
for n,e,o,st,c,l in sorted([r for r in arch if r[3]=='26.04'], key=lambda r:({'base':0,'config-engine':1,'swss-layer':2,'leaf':3}[r[5]],r[0])): L.append(f"| {n} | {c} | {l} | {len(e['imgs'])} |")
miss={r[0] for r in arch if r[3]!='26.04' and r[4]=='runtime'}
L+=['\n## Per container: runtime ARCHIVE packages lacking a 26.04 SDF\n','| container | runtime-missing total | leaf-specific | leaf-specific names |','|---|--:|--:|---|']
for i in sorted((VS|BCM)-{'docker-dash-engine'}):
    d=imgs[i]['debs']; m=[n for n in d if n in miss]; leaf=[n for n in m if n not in layer_of]
    L.append(f"| {i} | {len(m)} | {len(leaf)} | {', '.join(sorted(leaf))} |")
shared=[n for n in miss if n in layer_of]
L.append(f'\nShared-layer (base/config-engine/swss-layer) runtime packages lacking a 26.04 SDF — these hit every container: {len(shared)}\n')
for l in ('base','config-engine','swss-layer'): L.append(f"- {l}: " + ', '.join(sorted(n for n in shared if layer_of[n]==l)))
open(f'{OUT}/CHISEL-COVERAGE.md','w').write('\n'.join(L)+'\n'); print('\nreport written')
