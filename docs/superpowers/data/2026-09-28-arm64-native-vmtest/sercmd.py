#!/usr/bin/env python3
# usage: sercmd.py <socket> <timeout> <cmd...>   drive the VM serial console (logs in if needed)
import socket,sys,time,re
path,tmo=sys.argv[1],float(sys.argv[2]); cmd=' '.join(sys.argv[3:])
s=socket.socket(socket.AF_UNIX); s.connect(path); s.settimeout(0.5)
buf=b''
def rd(t):
    global buf; end=time.time()+t
    while time.time()<end:
        try:
            d=s.recv(65536)
            if d: buf+=d
        except socket.timeout: pass
def wait(pat,t):
    end=time.time()+t
    while time.time()<end:
        rd(0.5)
        if re.search(pat,buf.decode(errors='replace')): return True
    return False
s.send(b'\r'); rd(2)
txt=buf.decode(errors='replace')
if 'login:' in txt[-200:]:
    s.send(b'admin\r'); wait(r'Password:',15); s.send(b'YourPaSsWoRd\r'); wait(r'\$ $',30)
buf=b''
marker='__END_%d__'%int(time.time())
s.send(('stty -echo cols 250 2>/dev/null; echo '+marker+'; '+cmd+'; echo '+marker+'\r').encode())
end=time.time()+tmo
while time.time()<end:
    rd(0.5)
    if buf.decode(errors='replace').count(marker)>=3: break
out=re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\][0-9]+;[^\\\n]*\\|\r','',buf.decode(errors='replace'))
parts=out.split(marker)
print(parts[-2] if len(parts)>=3 else out)
