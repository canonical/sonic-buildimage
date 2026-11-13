# arm64 t0 run (papat, 2026-11-12)

Data and scripts behind the [arm64 t0 report](../../2026-11-12-sonic-mgmt-t0-arm64-run-report-en.md).
Host addresses are replaced by `<arm64-host>` and `<apt-proxy>`.

| File | Content |
|---|---|
| `compare-main-amd64-vs-arm64.txt` | `scripts/analyze2.py` output: the amd64 final rerun of the t0 report against the arm64 main run |
| `differing-cases-main.txt` | the 71 cases whose call outcome differs, grouped by file |
| `rerun-table.txt` | `scripts/rerun_table.py` output: every case of the 27 rerun files in the amd64 run, the arm64 main run, rerun A (platform alias) and rerun B (unchanged) |
| `tacacs-rerun.txt` | the nine TACACS-related files after the ptf fix, against amd64 |
| `compare-pr3-amd64-vs-arm64.txt` | the amd64 final rerun against the full arm64 rerun with canonical/sonic-mgmt#3 (report §6) |
| `handoffs-pr3.json` | the balancer's hand-overs in that rerun |
| `handoffs.json` | the balancer's hand-overs in the main run |
| `shards/` | `shard-arm-*` main run, `shard-evalA-*`/`shard-evalB-*` reruns, `shard-tac-*` TACACS rerun |
| `sonic-mgmt-aarch64-testbed.patch` | the local sonic-mgmt commit the main run used, now the first commit of canonical/sonic-mgmt#3: `sonic_aarch64.xml.j2`, its selection in `start_sonic_vm.yml`, undefine with `nvram` in `stop_sonic_vm.yml` |
| `eval-platform-alias.diff` | evaluation only: `sonic_basic_facts`/`dut_basic_facts` report `arm64-qemu_armv8a-r0` as `x86_64-kvm_x86_64-r0` (rerun A) |
| `images/docker-sonic-mgmt/Dockerfile.arm64` | upstream `e8bb4d24b` Dockerfile rendered with `docker_sonic_mgmt_whls=sonic_py_common-1.0-py3-none-any.whl`; the wheel comes from `scripts/repack-sonic-py-common.sh` |
| `images/docker-ptf/Dockerfile.arm64-202605` | upstream 202605 `50b78a3b5` Dockerfile rendered for arm64; the build context is that commit's `dockers/docker-ptf` with `tacacs_plus` and `ptf_tgen.sh` mode 0755, plus `sources.list.arm64` and the two `files/apt/apt.conf.d` files |
| `images/docker-ptf/Dockerfile.add-ptf-py3` | adds ptf-py3 from `scripts/extract-ptf-py3.sh` on top |

| Script | Role |
|---|---|
| `host-setup-arm.sh` | host packages, build prerequisites, binfmt through `binfmt.d`, kernel modules and host-wide sysctls for the containers, LXD |
| `build-arm.sh` | native build of `target/sonic-vs.bin` (`PLATFORM_ARCH=arm64` is required; `Makefile.work` defaults to amd64) |
| `make-vs-img.py`, `esp-fallback.sh`, `boot-test.sh` | install `sonic-vs.bin` through ONIE onto a 16 GB qcow2, point the removable boot path at SONiC's GRUB, boot once with a blank NVRAM |
| `launch-arm.sh`, `start-all-arm.sh`, `tb-bootstrap-arm.sh`, `stages.sh` | the LXD profile and containers, the per-testbed bootstrap, a stage summary |
| `rerun-tb.sh` | deploy-mg, then a file list, with or without the platform alias |
| `run2-tb.sh` | swap a testbed to another sonic-mgmt tree, deploy-mg, then its shard (the #3 rerun) |
| `ceos-arm-test.sh` | boot two cEOSarm containers and check the CLI |
| `collect-arm.sh`, `analyze2.py`, `rerun_table.py` | collection and comparison; `analyze2.py` uses `analyze.py` from the t0 run's data |

The balancer is `scripts/balancer2.py` of [the t0 run](../2026-11-11-sonic-mgmt-t0-run/scripts/), with `~/bal/config.json` listing `tb01`…`tb16`.
