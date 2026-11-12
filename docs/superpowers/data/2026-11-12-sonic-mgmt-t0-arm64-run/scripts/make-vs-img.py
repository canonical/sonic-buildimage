#!/usr/bin/env python3
"""Make an arm64 sonic-vs.img the way scripts/build_kvm_image.sh does on amd64: install sonic-vs.bin through ONIE.

usage: make-vs-img.py <workdir> <sonic-vs.bin> <onie.iso> <AAVMF_CODE> <AAVMF_VARS> <out.qcow2>
ONIE embeds itself on a blank 16G disk -> boots from disk -> onie-nos-install over HTTP -> stop at the reboot.
"""
import os, re, socket, subprocess, sys, time, http.server, threading, functools

work, image, iso, code, vars_tmpl, out = sys.argv[1:7]
os.makedirs(work, exist_ok=True)
varsf = f'{work}/vars.fd'
ser, mon, log = f'{work}/serial.sock', f'{work}/monitor.sock', f'{work}/serial.log'
for f in (out, varsf, ser, mon, log):
    if os.path.exists(f): os.remove(f)
subprocess.run(['qemu-img', 'create', '-q', '-f', 'qcow2', out, '16G'], check=True)
subprocess.run(['cp', vars_tmpl, varsf], check=True)
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=os.path.dirname(os.path.abspath(image)))
httpd = http.server.ThreadingHTTPServer(('0.0.0.0', 8089), handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
url = f'http://10.0.2.2:8089/{os.path.basename(image)}'
qemu = subprocess.Popen([
    'qemu-system-aarch64', '-machine', 'virt,gic-version=3', '-accel', 'kvm', '-cpu', 'host', '-smp', '4', '-m', '8192',
    '-drive', f'if=pflash,format=raw,readonly=on,file={code}', '-drive', f'if=pflash,format=raw,file={varsf}',
    '-device', 'virtio-scsi-pci,id=scsi0',
    '-drive', f'file={out},if=none,id=hd0,format=qcow2', '-device', 'scsi-hd,drive=hd0,bootindex=1',
    '-drive', f'file={iso},media=cdrom,if=none,id=cd0,readonly=on', '-device', 'scsi-cd,drive=cd0,bootindex=0',
    '-netdev', 'user,id=m0', '-device', 'virtio-net-pci,netdev=m0',
    '-display', 'none', '-monitor', f'unix:{mon},server,nowait',
    '-chardev', f'socket,id=s0,path={ser},server=on,wait=off,logfile={log}', '-serial', 'chardev:s0'],
    stdout=subprocess.DEVNULL, stderr=open(f'{work}/qemu.err', 'w'))
for _ in range(200):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(ser); break
    except OSError:
        time.sleep(0.05)
s.settimeout(0.2)
buf = b''
T0 = time.time()

def rd(t):
    global buf
    end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(65536)
            if d: buf += d
        except socket.timeout:
            pass

def txt():
    return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\r', '', buf.decode(errors='replace'))

def wait(pat, t, since=0):
    end = time.time() + t
    while time.time() < end:
        rd(0.3)
        m = re.search(pat, txt()[since:])
        if m: return m
        if qemu.poll() is not None: return None
    return None

def step(msg):
    print(f'[{time.time() - T0:7.1f}s] {msg}', flush=True)

def monitor(cmd):
    m = socket.socket(socket.AF_UNIX); m.connect(mon); m.settimeout(2)
    m.send((cmd + '\n').encode()); time.sleep(0.5)
    try: m.recv(65536)
    except socket.timeout: pass
    m.close()

def send(line):
    s.send((line + '\r').encode())

def fail(msg):
    step('FAIL: ' + msg)
    print('----- last console output -----'); print(txt()[-3000:])
    qemu.kill(); sys.exit(1)

if not wait(r'ONIE: Executing installer: file:///lib/onie/onie-updater', 180): fail('ONIE embed never started')
step('ONIE embed started; ejecting the ISO')
monitor('eject -f cd0')
mark = len(txt())
if not wait(r'(?i)rebooting|reboot: Restarting', 600, mark): fail('ONIE embed did not finish')
step('ONIE embedded; rebooting')
mark = len(txt())
if not wait(r'Please press Enter to activate this console', 300, mark): fail('ONIE from disk did not come up')
send(''); wait(r'ONIE:/ #', 30, mark)
send('onie-discovery-stop'); wait(r'ONIE:/ #', 60, len(txt()) - 5)
mark = len(txt())
step(f'running onie-nos-install {url}')
send(f'onie-nos-install {url}')
end = time.time() + 1800
while time.time() < end:
    m = wait(r'Do you still wish to install this image\? \[y/n\]|ONIE: NOS install successful|Installed SONiC base image SONiC-OS successfully', 60, mark)
    if not m:
        if qemu.poll() is not None: fail('qemu exited during install')
        continue
    mark = len(txt())
    if m.group(0).startswith('Do you still wish'):
        fail('installer asked for the ASIC type: the platform alias is missing from the image')
    step('installer: ' + m.group(0))
    if 'NOS install successful' in m.group(0): break
else:
    fail('install did not finish in 30 min')
# stop before SONiC's first boot, as build_kvm_image.sh does
if not wait(r'(?i)reboot: Restarting|GNU GRUB', 300, mark): fail('no reboot after the install')
qemu.kill(); qemu.wait()
step(f'done: {out}')
