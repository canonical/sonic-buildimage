import lzma, glob, json, os, re, subprocess, sys, urllib.request, concurrent.futures as cf, urllib.parse
import yaml
R='/home/sheldon-qi/chisel-releases'; OUT='/tmp/pkgscan-out'; DL='/tmp/debs-cov'; os.makedirs(DL,exist_ok=True)
MIRROR='http://archive.ubuntu.com/ubuntu/'
# 1. index with Filename (release -> security -> updates; last wins)
idx={}
for suite in ('resolute','resolute-security','resolute-updates'):
    for comp in ('main','universe'):
        cur={}
        for line in lzma.open(f'/tmp/ubuntu-idx/{suite}_{comp}_Packages.xz','rt',encoding='utf-8',errors='replace'):
            if line=='\n':
                if 'Package' in cur: idx[cur['Package']]=cur
                cur={}; continue
            if line[0] in ' \t': continue
            k,_,v=line.partition(':'); cur[k]=v.strip()
        if 'Package' in cur: idx[cur['Package']]=cur
# 2. our covered ARCHIVE set
S26={os.path.basename(f)[:-5] for f in glob.glob(f'{R}/slices/*.yaml')}
imgs={os.path.basename(f)[:-5]:json.load(open(f)) for f in glob.glob(f'{OUT}/docker-*.json')}
sb={}
for f in glob.glob('/home/sheldon-qi/sonic-buildimage-resolute/target/debs/resolute/*.deb'):
    n,v,_=os.path.basename(f)[:-4].split('_',2); sb.setdefault(n,set()).add(urllib.parse.unquote(v).split(':')[-1])
ours=set()
for i,d in imgs.items():
    if i=='docker-dash-engine': continue
    for n,v in d['debs'].items():
        if n in sb and v['Version'].split(':')[-1] in sb[n]: continue
        if n in idx and n in S26: ours.add(n)
print('covered ARCHIVE pkgs in our set:', len(ours), flush=True)
# 3. download
def fetch(n):
    fn=idx[n]['Filename']; dst=f"{DL}/{os.path.basename(fn)}"
    if not os.path.exists(dst):
        try: urllib.request.urlretrieve(MIRROR+fn, dst)
        except Exception as e: return n,None,repr(e)
    return n,dst,None
debs={}
with cf.ThreadPoolExecutor(8) as ex:
    for n,dst,err in ex.map(fetch, sorted(ours)):
        if err: print('DL FAIL',n,err, flush=True)
        else: debs[n]=dst
print('downloaded', len(debs), flush=True)
# 4. compare
def glob_re(p):
    out=''; i=0
    while i<len(p):
        c=p[i]
        if p.startswith('**',i): out+='.*'; i+=2; continue
        if c=='*': out+='[^/]*'
        elif c=='?': out+='[^/]'
        else: out+=re.escape(c)
        i+=1
    return re.compile('^'+out+'$')
DOC_RE=re.compile(r'^/usr/share/(man|doc|doc-base|lintian|info|bash-completion|zsh|fish|menu|pixmaps|applications)/|^/etc/bash_completion\.d/|^/usr/share/doc/')
LEGAL_RE=re.compile(r'^/usr/share/doc/[^/]+/(copyright|NOTICE|LICENSE|COPYING|AUTHORS)(\.txt|\.gz)?$')
LOCALE_RE=re.compile(r'^/usr/share/locale/')
def deb_files(path):
    out=subprocess.run(['dpkg-deb','-c',path],capture_output=True,text=True).stdout
    files=[]
    for line in out.splitlines():
        parts=line.split(None,5)
        if len(parts)<6: continue
        perm,rest=parts[0],parts[5]
        p=rest.split(' -> ')[0]
        if perm.startswith('d') or p.endswith('/'): continue
        p=p[1:] if p.startswith('./') or p.startswith('.') and p[1:2]=='/' else p
        if not p.startswith('/'): p='/'+p
        files.append((p,perm[0]))
    return files
def maint_scripts(path):
    out=subprocess.run(['dpkg-deb','-I',path],capture_output=True,text=True).stdout
    return sorted(s for s in ('preinst','postinst','prerm','postrm') if re.search(rf'\b{s}\b',out.split('\n\n')[0] if False else out))
res={}
for n in sorted(debs):
    sdf=yaml.safe_load(open(f'{R}/slices/{n}.yaml'))
    pats=[]; has_mutate=False; nslices=0
    for sname,body in (sdf.get('slices') or {}).items():
        nslices+=1
        if body and body.get('mutate'): has_mutate=True
        for k,opt in ((body or {}).get('contents') or {}).items():
            if k.endswith('/') and not (opt and 'make' in opt) : pass
            pats.append(glob_re(k))
            if isinstance(opt,dict) and opt.get('copy'): pats.append(glob_re(opt['copy']))
    files=deb_files(debs[n])
    unc=[p for p,t in files if not any(r.match(p) for r in pats)]
    real=[p for p in unc if not (DOC_RE.match(p) and not LEGAL_RE.match(p)) and not LOCALE_RE.match(p)]
    legal_unc=[p for p in unc if LEGAL_RE.match(p)]
    res[n]={'files':len(files),'uncovered':len(unc),'doc_locale':len(unc)-len(real),'real':real,'legal_unc':legal_unc,'slices':nslices,'mutate':has_mutate,'maint':maint_scripts(debs[n]),'version':idx[n]['Version']}
    print(f"{n}: {len(files)} files, {len(unc)} uncovered ({len(real)} real), slices={nslices} mutate={has_mutate} maint={res[n]['maint']}", flush=True)
json.dump(res, open(f'{OUT}/slice-completeness.json','w'), indent=1)
full=[n for n in res if not res[n]['real']]; gaps=[n for n in res if res[n]['real']]
print(f"\nFULL (all non-doc files covered): {len(full)}  GAPS: {len(gaps)}")
print('with maintainer scripts:', sum(1 for n in res if res[n]['maint']), 'of which SDF has mutate:', sum(1 for n in res if res[n]['maint'] and res[n]['mutate']))
