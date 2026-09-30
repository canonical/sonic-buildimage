#!/usr/bin/env python3
"""Install a SONiC arm64 image through ONIE end to end under KVM and boot it.

usage: onie-install-test.py <workdir> <sonic-vs.bin> <onie.iso> <AAVMF_CODE> <AAVMF_VARS>
Phases: ONIE embeds itself on a blank disk -> reboot into ONIE from disk ->
onie-nos-install over HTTP -> reboot -> ONIE-installed GRUB boots SONiC -> login.
"""
import os, re, socket, subprocess, sys, time, http.server, threading, functools

work, image, iso, code, vars_tmpl = sys.argv[1:6]
os.makedirs(work, exist_ok=True)
disk, varsf = f'{work}/disk.qcow2', f'{work}/vars.fd'
ser, mon, log = f'{work}/serial.sock', f'{work}/monitor.sock', f'{work}/serial.log'
for f in (disk, varsf, ser, mon, log):
    if os.path.exists(f): os.remove(f)
subprocess.run(['qemu-img', 'create', '-q', '-f', 'qcow2', disk, '64G'], check=True)
subprocess.run(['cp', vars_tmpl, varsf], check=True)

# serve the image to the guest (QEMU user networking maps the host to 10.0.2.2)
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=os.path.dirname(os.path.abspath(image)))
httpd = http.server.ThreadingHTTPServer(('0.0.0.0', 8089), handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
url = f'http://10.0.2.2:8089/{os.path.basename(image)}'

qemu = subprocess.Popen([
    'qemu-system-aarch64', '-machine', 'virt,gic-version=3', '-accel', 'kvm', '-cpu', 'host', '-smp', '4', '-m', '8192',
    '-drive', f'if=pflash,format=raw,readonly=on,file={code}', '-drive', f'if=pflash,format=raw,file={varsf}',
    '-device', 'virtio-scsi-pci,id=scsi0',
    '-drive', f'file={disk},if=none,id=hd0,format=qcow2', '-device', 'scsi-hd,drive=hd0,bootindex=1',
    '-drive', f'file={iso},media=cdrom,if=none,id=cd0,readonly=on', '-device', 'scsi-cd,drive=cd0,bootindex=0',
    '-netdev', 'user,id=m0,hostfwd=tcp::3043-:22', '-device', 'virtio-net-pci,netdev=m0',
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

# 1. ONIE recovery ISO in embed mode installs ONIE onto the disk
if not wait(r'ONIE: Executing installer: file:///lib/onie/onie-updater', 180): fail('ONIE embed never started')
step('ONIE embed started; ejecting the ISO so the next boot comes from disk')
monitor('eject -f cd0')
mark = len(txt())
if not wait(r'(?i)rebooting|reboot: Restarting', 600, mark): fail('ONIE embed did not finish')
step('ONIE embedded; rebooting')

# 2. ONIE from disk
mark = len(txt())
if not wait(r'Please press Enter to activate this console', 300, mark): fail('ONIE from disk did not come up')
m = re.search(r'GNU GRUB +version ([0-9.]+)', txt()[mark:])
step(f'ONIE booted from disk (its GRUB: {m.group(1) if m else "?"})')
send(''); wait(r'ONIE:/ #', 30, mark)
send('onie-discovery-stop'); wait(r'ONIE:/ #', 60, len(txt()) - 5)
mark = len(txt())
step(f'running onie-nos-install {url}')
send(f'onie-nos-install {url}')

# 3. SONiC installer; answer the ASIC-type prompt that an arm64 vs image triggers
end = time.time() + 1800
while time.time() < end:
    m = wait(r'Do you still wish to install this image\? \[y/n\]|Installed SONiC base image SONiC-OS successfully|ONIE: NOS install successful|(?i:error|failed|failure)', 60, mark)
    if not m:
        if qemu.poll() is not None: fail('qemu exited during install')
        continue
    t = m.group(0)
    mark = len(txt())
    if t.startswith('Do you still wish'):
        step('installer: ASIC type prompt (platform not in platforms_asic) -> answering y'); send('y'); continue
    if 'successful' in t or 'successfully' in t:
        step('SONiC installer: ' + t); break
    step('installer output matched: ' + t)
else:
    fail('install did not finish in 30 min')

# 4. reboot into SONiC via the GRUB that the installer set up
mark = len(txt())
m = wait(r'GNU GRUB +version ([0-9.]+)', 600, mark)
if not m: fail('no GRUB menu after install')
step(f'GRUB {m.group(1)} menu after install')
entries = re.findall(r'\*?(SONiC-OS-[^\s|]+|ONIE[^\n|]{0,30})', txt()[mark:])
step('GRUB entries seen: ' + ', '.join(dict.fromkeys(e.strip() for e in entries)))
for e in re.findall(r'error: [^\n]+', txt()[mark:]):
    step('GRUB said: ' + e.strip())

def ssh_banner():
    try:
        c = socket.create_connection(('127.0.0.1', 3043), timeout=3); c.settimeout(5)
        b = c.recv(64); c.close(); return b.startswith(b'SSH-')
    except OSError:
        return False

fatal = r'error: (invalid magic number|you need to load the kernel first|file `[^\n]*vmlinuz[^\n]*not found|no such partition)'
end, seen_kernel = time.time() + 900, False
while time.time() < end:
    rd(2)
    t = txt()[mark:]
    fm = re.search(fatal, t)
    if fm: fail('GRUB could not load the SONiC kernel: ' + fm.group(0))
    km = re.search(r'Linux version (\S+)', t)
    if km and not seen_kernel:
        seen_kernel = True; step(f'SONiC kernel {km.group(1)} printing on the serial console')
    if 'sonic login:' in t:
        step('SONiC serial login prompt reached'); break
    if ssh_banner():
        step('SONiC sshd answering on the management port' + ('' if seen_kernel else ' (kernel printed nothing on ttyAMA0)')); break
    if qemu.poll() is not None: fail('qemu exited')
else:
    fail('SONiC never came up (no serial login, no ssh)')

# 5. collect state over ssh (serial may carry no console)
time.sleep(300)
cmd = ('cat /proc/cmdline; echo ---; grep onie_platform /host/machine.conf; echo ---; show version; echo ---; '
       'show platform summary; ls -la /usr/share/sonic/device/ | grep -E "arm64-qemu|x86_64-kvm_x86_64-r0"; dpkg-query -W sonic-platform-vs; echo ---; '
       'ls -la /host/image-*/platform/; sudo od -An -tx1 -N4 /host/image-*/boot/vmlinuz-*; echo ---; '
       'sudo grep -nE "^serial|^#|terminal_|menuentry|linux +/" /host/grub/grub.cfg; echo ---; systemctl is-system-running; '
       'systemctl --failed --no-legend; echo ---; docker ps --format "{{.Names}} {{.Status}}" | sort; echo ---; '
       'echo PORTS_APPL=$(redis-cli -n 0 keys "PORT_TABLE:Ethernet*" | wc -l) PORTS_ASIC=$(redis-cli -n 1 keys "ASIC_STATE:SAI_OBJECT_TYPE_PORT:*" | wc -l) ROUTES_ASIC=$(redis-cli -n 1 keys "ASIC_STATE:SAI_OBJECT_TYPE_ROUTE_ENTRY:*" | wc -l); '
       'show ip bgp summary | grep -E "local AS|Peers"; redis-cli -n 4 hget "DEVICE_METADATA|localhost" hwsku; redis-cli -n 4 hget "DEVICE_METADATA|localhost" mac')
r = subprocess.run(['sshpass', '-p', 'YourPaSsWoRd', 'ssh', '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
                    '-o', 'ConnectTimeout=20', '-p', '3043', 'admin@127.0.0.1', cmd], capture_output=True, text=True, timeout=180)
print('----- SONiC state (ssh) -----'); print(r.stdout); print(r.stderr[-500:])
step('done; VM left running (kill qemu-system-aarch64 to stop)')
