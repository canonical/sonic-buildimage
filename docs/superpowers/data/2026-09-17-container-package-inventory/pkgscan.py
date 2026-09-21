#!/usr/bin/env python3
"""Scan docker-save (OCI layout) .gz tarballs: extract final dpkg status + python dist-info list."""
import sys, os, io, json, tarfile, subprocess, re

def open_outer(path):
    dec = 'pigz' if subprocess.run(['which','pigz'],capture_output=True).returncode==0 else 'gzip'
    p = subprocess.Popen([dec,'-dc',path], stdout=subprocess.PIPE)
    return tarfile.open(fileobj=p.stdout, mode='r|'), p

def parse_status(text):
    pkgs = {}
    for block in text.split('\n\n'):
        d = {}
        cur = None
        for line in block.split('\n'):
            if not line: continue
            if line[0] in ' \t':
                if cur: d[cur] += '\n' + line
                continue
            k, _, v = line.partition(':')
            cur = k; d[k] = v.strip()
        if 'Package' in d and d.get('Status','').endswith('installed'):
            pkgs[d['Package']] = {k: d.get(k,'') for k in ('Version','Architecture','Installed-Size','Priority','Section','Essential','Source','Depends')}
    return pkgs

PYRE = re.compile(r'^(usr/(local/)?lib/python3(\.\d+)?/(dist|site)-packages)/([^/]+\.(dist-info|egg-info))/?$')

def scan(path):
    outer, proc = open_outer(path)
    manifest = None
    layers = {}   # digest -> {'status': str|None, 'py_add': set, 'py_wh': set}
    for m in outer:
        if m.name == 'manifest.json':
            manifest = json.load(outer.extractfile(m)); continue
        if not m.isfile() or not m.name.startswith('blobs/sha256/'): continue
        f = outer.extractfile(m)
        head = f.read(512)
        # layer tars begin with a ustar header; config/manifest json blobs don't
        if b'ustar' not in head[257:265]:
            continue
        digest = m.name.split('/')[-1]
        inner = tarfile.open(fileobj=io.BytesIO(head + f.read()), mode='r:')
        rec = {'status': None, 'py_add': set(), 'py_wh': set()}
        for im in inner:
            n = im.name.lstrip('./')
            if n == 'var/lib/dpkg/status' and im.isfile():
                rec['status'] = inner.extractfile(im).read().decode('utf-8','replace')
            mm = PYRE.match(n)
            if mm:
                base = os.path.basename(n.rstrip('/'))
                if base.startswith('.wh.'):
                    rec['py_wh'].add((mm.group(1), base[4:]))
                else:
                    rec['py_add'].add((mm.group(1), base))
        layers[digest] = rec
    proc.wait()
    order = []
    for L in manifest[0]['Layers']:
        order.append(L.split('/')[-1])
    status = None; py = set()
    for dg in order:
        rec = layers.get(dg)
        if not rec: continue
        if rec['status'] is not None: status = rec['status']
        py -= rec['py_wh']; py |= rec['py_add']
    pkgs = parse_status(status) if status else {}
    pyl = sorted(f"{d}/{b}" for d,b in py)
    return {'image': os.path.basename(path), 'n_layers': len(order), 'debs': pkgs, 'python': pyl}

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    for p in sys.argv[2:]:
        name = os.path.basename(p).replace('.gz','')
        try:
            r = scan(p)
            json.dump(r, open(f'{out}/{name}.json','w'), indent=1)
            print(f"{name}: {len(r['debs'])} debs, {len(r['python'])} py dists, {r['n_layers']} layers", flush=True)
        except Exception as e:
            print(f"{name}: ERROR {e!r}", flush=True)
