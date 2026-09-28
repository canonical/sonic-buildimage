import struct,sys,subprocess
b=open(sys.argv[1],'rb').read()
assert b[4:8]==b'zimg', b[:8]
off,size=struct.unpack_from('<II',b,8)
comp=b[24:32].rstrip(b'\0').decode()
print('zboot payload off',off,'size',size,'comp',comp)
payload=b[off:off+size]
out=subprocess.run(['zstd','-dc'] if comp=='zstd' else ['gzip','-dc'],input=payload,capture_output=True)
open(sys.argv[2],'wb').write(out.stdout); print('raw Image',len(out.stdout),out.stdout[56:60])
