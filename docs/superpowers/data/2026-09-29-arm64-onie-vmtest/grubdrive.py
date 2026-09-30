import socket,sys,time,re
path=sys.argv[1]; cmds=sys.argv[2:]
for _ in range(200):
    try: s=socket.socket(socket.AF_UNIX); s.connect(path); break
    except OSError: time.sleep(0.05)
s.settimeout(0.2); buf=b''
def rd(t):
    global buf; end=time.time()+t
    while time.time()<end:
        try:
            d=s.recv(65536)
            if d: buf+=d
        except socket.timeout: pass
def txt(): return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\r','',buf.decode(errors='replace'))
def wait(p,t):
    end=time.time()+t
    while time.time()<end:
        rd(0.2)
        if re.search(p,txt()): return True
    return False
if not wait(r'GNU GRUB',60): print('NO GRUB MENU'); print(txt()[-800:]); sys.exit(1)
got=False
for _ in range(10):
    s.send(b'c')
    if wait(r'grub>',1.5): got=True; break
if not got: print('NO GRUB PROMPT'); print(txt()[-800:]); sys.exit(1)
for c in cmds:
    s.send(b'\x15'); rd(0.3); mark=len(txt()); s.send((c+'\r').encode())
    if c=='boot':
        wait(r'Kernel panic|end Kernel panic|Unable to mount root',120); rd(2)
        out=txt()[mark:]; keep=[l for l in out.splitlines() if re.search(r'Booting|Linux version|Machine model|Kernel command line|panic|Unable to mount|EFI stub|error',l)]
        print('### boot'); print('\n'.join(keep[:12])); continue
    wait(r'grub> $',30); out=txt()[mark:]
    print('### '+c); print('\n'.join(l for l in out.splitlines() if l.strip() and not l.startswith('grub>'))[-600:])
