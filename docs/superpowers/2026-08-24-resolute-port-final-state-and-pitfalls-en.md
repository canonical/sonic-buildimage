# Moving SONiC 202605 onto Ubuntu 26.04: final state and pitfalls

The final state here is `202605_resolute_sheldon` at `648c8121aa` (checked 2026-08-27), measured against `ba3fb8d5f5` (the merge-base all three branches share with `sonic-net/202605`).

One distinction to keep: **the last full from-scratch rebuild was done on `2957b9e3fd`** (2026-08-23). `_sheldon` has since advanced nine commits to `648c8121aa`, and **those nine have not been through a full rebuild**. The ones with real consequences — the registry and test-skip settings moving up, FIPS defaulting off, flashrom returning to a source build, the base-system mirror cleanup — are covered where they belong below. The other three are hygiene: two `sonic-utilities` gitlink bumps for py3.14 test and CLI-plugin fixes, and the removal of a duplicated `libpam0g-dev` from the slave image.

Every path and line number below refers to the **build repository**, `~/sonic-buildimage-resolute`, at that commit. The docs repository (`~/sonic-buildimage`, branch `202605_resolute_doc`) holds the upstream version of those same files, so the line numbers will not match there. Do not go looking by line number on that side.

---

## 1. Where it stands

213 files, `+2699 / −823`, 190 commits.

On 2026-08-23 we did a rebuild that was genuinely from scratch, and the tree at `2957b9e3fd` built both platforms untouched. Nothing was edited mid-build, no job counts were lowered, no environment variable was used to route around anything. The artifacts are `target/sonic-vs.bin` (2.5 GB, 16:28) and `target/sonic-broadcom.bin` (2.1 GB, 17:38).

One thing has to be stated first, or "it built" reads as a stronger claim than it is. `BUILD_SKIP_TEST = y`, and `slave.mk` skips several classes of package test accordingly. So "no environment variable was used to route around anything" is literally true, but the tests were skipped by configuration rather than passing.

Where that setting lives just changed. During the 08-23 run it sat in `rules/config.user`, which only `_sheldon` carries; `648c8121aa` moved it into the version-controlled `rules/config`. Passing `BUILD_SKIP_TEST=n` on the command line still overrides it.

Do **not** read that as the state of every branch, though. This final configuration currently exists only on `_sheldon` and on the complete formal stack `_real`:

```
_mech       DEFAULT_CONTAINER_REGISTRY ?= publicmirror.azurecr.io   INCLUDE_FIPS ?= y   BUILD_SKIP_TEST ?= n
_real       DEFAULT_CONTAINER_REGISTRY =                            INCLUDE_FIPS ?= n   BUILD_SKIP_TEST = y
_sheldon    same as _real
production  same as _mech (still at the baseline)
```

So building `_mech` on its own still hits the registry failure, still enables FIPS, and still runs the tests. `_mech` was never meant to be independently buildable; it is the first layer of a reviewable split.

"From scratch" here means the cache directories and `fsroot*` were emptied, not that caching was switched off. `rules/config.user` still sets `SONIC_DPKG_CACHE_METHOD = rwcache` against `/var/cache/sonic/artifacts`, and ccache and the docker layer cache are both on; they were simply empty, so every deb really was rebuilt. The order of the wipe matters: `fsroot*` is root-owned, so it needs `sudo rm` before `git clean`, or clean fails on permissions. This is a different thing from the `SONIC_DPKG_CACHE_METHOD=none` in 4.3, which bypasses the cache *without* clearing it, to rule out having been handed an old deb.

`os-release` inside the image says Ubuntu 26.04, and the kernel is `linux-sonic 7.0.0-1002-sonic` from Launchpad. The broadcom image has run on a Dell S5232F (TD3 / XGS): BGP up on both v4 and v6, 215 routes in ASIC_DB, traffic passing end to end.

The changes land in seven layers, very unevenly. `slave.mk` and `rules/` is by far the largest; the target rootfs layer is only a handful of edits.

---

## 2. Where Ubuntu and Debian actually differ

We started out thinking this was a `FROM` edit. What actually stopped us falls into five groups, and only one of them is "the toolchain is too new".

**Structural differences** are the worst of the five, because they never produce a version error. They just behave differently. Ubuntu splits grub2 into `src:grub2` and `src:grub2-unsigned`, and `grub-efi-amd64-bin` comes out of the second one. Kernel modules ship as a separate `linux-modules` deb, where Debian bundled them into the image. The `resolvconf` package does not exist in the Ubuntu archive at all; `systemd-resolved` declares `Provides/Replaces/Conflicts` and takes the name. And `rsyslog` and `hostname` ship enforced AppArmor profiles, which Debian does not. Those last two stayed hidden until we deployed onto real hardware.

**The toolchain being newer** was the most predictable group and also the biggest: GCC 15 defaulting to C23, Python 3.14 enforcing PEP 668 throughout, cmake 4.x, boost defaulting to 1.90, doxygen 1.14+, SWIG 4.4. There is one counter-intuitive thing here, though: newer is not automatically better. We adapted boost to 1.88 across a full round of work and then went back to 1.83, because 1.83 is what trixie and bookworm default to, and aligning with it is what keeps the `io_service` code in our submodules compiling. Boost 1.90's header-only direction would have widened the migration considerably.

**Linux 7.0's kernel API drift** only lands on the broadcom layer, but it lands across a wide surface: the `timer` API, `bin_attribute` read/write callbacks turning const, `MODULE_IMPORT_NS` becoming a string form, the kbuild arch-tree layout, objtool, `-fms-extensions`, the `i2c_register_spd` guard, `device_find_child`, the `GPIOF_*` constants, `EXPORT_SYMBOL_NS_GPL`. A dozen or so categories.

**Upstream hardcodes the distro codename as a literal.** This group is large in edit count and uniformly easy: `trixie` sits in leaf Dockerfiles' `ARG BASE`, in `slave.mk`'s per-distro container sets, in the FIPS makefile which has no resolute block at all, and in an apt source generator that only knows the Debian component layout.

**dpkg and debhelper got stricter.** dpkg 1.23 strictly parses the `Maintainer` field and changelog trailers, so a pile of packages' non-standard spellings stop passing. And debhelper emits dbgsym as `.ddeb` while SONiC looks for `.deb` everywhere.

---

## 3. The seven layers

### 3.1 The slave image and the build entry points

`BLDENV=resolute` is now the default build environment. `Makefile:9` adds `NORESOLUTE ?= 0`, `Makefile:43-44` turns that into `BUILD_RESOLUTE=1`, and `Makefile:70-74` plus `Makefile:121` pass `BLDENV=resolute` down the recursion. `Makefile.work:132-133` then translates it into `SLAVE_DIR = sonic-slave-resolute`.

Only five files under `sonic-slave-resolute/` are version-controlled: the 862-line `Dockerfile.j2`, the 30-line `Dockerfile.user.j2`, and three small ones — `buildflags.conf`, `docker.sources`, `pip.conf`. Everything else in that directory (`Dockerfile`, the `.log` files, `files/`, `vcache/`) is build output and is not in the repository.

`buildflags.conf` has exactly one meaningful line in it, but that line is the master switch for the whole GCC 15 problem:

```
# line 4 of the file; it is one physical line, wrapped here for width
APPEND CFLAGS -std=gnu17 -Wno-error=incompatible-pointer-types
              -Wno-error=int-conversion -Wno-error=discarded-qualifiers
```

SONiC is full of K&R-style function prototypes, which C23 simply rejects, and a few warnings became errors in GCC 15. This line pulls every `dpkg-buildpackage` build back to gnu17. It started life as an inline `sed` against the Dockerfile; `8f4921cb8d` turned it into a static file. The inline sed was not idempotent, and a static file can be reviewed and diffed.

`pip.conf` is a `[global]` section with one setting under it, `break-system-packages = true`. Making it global configuration rather than a flag on individual commands is what gets it inherited by every container built on this base. There is one exception: `docker-dash-engine`'s base is an external p4lang image that does not inherit our `pip.conf`, so it has to say so explicitly in its own Dockerfile.

`docker.sources` is deb822 format pointing at `download.docker.com/linux/ubuntu`. docker-ce's Ubuntu pool is separate from its Debian pool, and the version suffix changes from `~debian.13~` to `~ubuntu.26.04~`.

Then there is the registry problem, which used to be the one that bit hardest. Upstream's default for `DEFAULT_CONTAINER_REGISTRY` in `rules/config` is `publicmirror.azurecr.io`, and `Makefile.work:157-158` appends a trailing slash to turn it into a prefix. So the slave's `FROM ubuntu:resolute` becomes `FROM publicmirror.azurecr.io/ubuntu:resolute` and the build dies on:

```
ERROR: failed to solve: publicmirror.azurecr.io/ubuntu:resolute: not found
```

That internal mirror mirrors Debian. Querying it for `ubuntu:resolute` returns `no such manifest`, while `docker.io/ubuntu:resolute` exists.

This **used to be** a hard dependency, and only `rules/config.user` on `_sheldon` set it empty, which is why a colleague building from a formal branch ran into it. `648c8121aa` has since moved the override into the version-controlled `rules/config:366` (`DEFAULT_CONTAINER_REGISTRY =`, plain empty), so on `_sheldon` and `_real` nothing needs copying; `_mech` and the production branch still hold the old defaults (see the table in chapter 1). The same commit put `BUILD_SKIP_TEST = y` at `rules/config:404`.

Worth noting that this is the first time `rules/config` has entered the diff at all. Until now the port never touched it and relied entirely on `config.user` overrides, which is precisely why formal branches came up short.

The workaround is worth recording anyway, because the shape of the trap recurs. The advice at the time was to copy `config.user` over from `_sheldon`, and that advice had an ordering problem: `make reset` runs `git clean -xfdf` (`Makefile.work:767`), and `-x` removes ignored files too. On `_sheldon` the file is force-added to version control, so `clean` leaves it alone; copied onto a formal branch it is merely an untracked, ignored file, and **reset deletes it**. Anything solved by dropping a machine-local file into an ignored path has to survive `make reset` first.

`rules/config.user` still exists on `_sheldon`, but the settings in it that still take **effect** are all machine-specific: `PLATFORM ?= vs`, `SONIC_DPKG_CACHE_METHOD = rwcache`, `SONIC_DPKG_CACHE_SOURCE`, `SONIC_VERSION_CACHE_METHOD = none`, and the ccache and docker-layer-cache switches. Copying it no longer decides whether a build starts; if you do copy it, the directory `SONIC_DPKG_CACHE_SOURCE` names has to exist with the right permissions.

Three lines in it are now pure no-ops, and they are worth a mention because they show why `?=` is deceptive in this build system. `Makefile.work` does `include rules/config` before `-include rules/config.user`, so any assignment in config.user that shadows a name already set in `rules/config` arrives too late. `INCLUDE_FIPS ?= y` cannot override the `?= n` already fixed at `rules/config:381` (see 3.5); `DEFAULT_CONTAINER_REGISTRY =` and `BUILD_SKIP_TEST = y` are now duplicates of `rules/config:366` and `:404`, left behind when `648c8121aa` moved those settings up. `PLATFORM ?= vs` is the opposite case and does take effect, since `rules/config` never defines it; passing `make PLATFORM=broadcom` on the command line is still the better habit than letting a machine-local file pick the build target.

On the apt side, `scripts/build_mirror_config.sh` and `files/apt/sources.list.j2` grew the Ubuntu component layout (`main restricted universe multiverse`, and `-updates` and `-security` treated as separate suites). Debian's `main contrib non-free` does not apply.

### 3.2 The build graph

The largest layer, and the goal fits in one line: **keep the diff as small as possible, given that only resolute has to work.**

One premise needs stating, or many of the trade-offs below look arbitrary: we **no longer require the trixie build to pass**. The trixie variants are left untouched not so they keep working, but because touching them would enlarge the diff and buy nothing. The same reasoning applies to anything that is not packaged into the deployed image: use the original, because there is no functional difference today and a change would be pure noise.

That principle accounts for several things later on that look like leftover mess: grub2's two `.patch` files still sitting in `src/grub2/patch/` (3.3), all three `mpdecimal` files present with only the registration line commented out (3.3), `src/libnl3/Makefile` being dead code after the move to an online deb (3.3), and `rules/iproute2.mk` wrapped entirely in `ifeq ($(BLDENV),trixie)` and never touched (4.4). None of those are oversights; cleaning them up simply is not worth the diff.

The concrete method follows from this: copy and rename rather than edit trixie in place, since editing leaves a diff on every file it touches.

`slave.mk` takes six groups of changes. Only the path definitions and the `mkdir`s are purely additive; the rest are replacements or dependency removals. Lines `51-53` add `RESOLUTE_DEBS_PATH` / `RESOLUTE_FILES_PATH` / `RESOLUTE_PHONY_PATH`, and `143-145` `mkdir -p` them in the `configure` target. Line `76` sets `IMAGE_DISTRO := resolute`. Line `81` adds resolute to a `$(filter ...)` list. Line `1015` adds `--force-depends` to the platform-modules deb install, because the kernel modules they depend on are not installed yet at that point, so the ordering check fails even though the dependency is satisfied later (`1014` is the comment explaining it). And both the RFS prerequisites from line `1500` and the installer prerequisites from line `1570` now list the split grub2 debs individually and drop `LINUX_KBUILD` entirely, since Ubuntu's `linux-sonic` ships no kbuild deb.

The `IMAGES` block has no resolute-specific branch, which is the shape review asked for. resolute goes through the existing `else` arm, where a filter-out drops every older distro's container set and resolute's containers land in the default set by construction:

```make
DOCKER_IMAGES = $(filter-out $(SONIC_JESSIE_DOCKERS) $(SONIC_STRETCH_DOCKERS) \
    $(SONIC_BUSTER_DOCKERS) $(SONIC_BULLSEYE_DOCKERS) $(SONIC_BOOKWORM_DOCKERS) \
    $(SONIC_TRIXIE_DOCKERS),$(SONIC_DOCKER_IMAGES))
```

That line only works because of the other half of the job, done across 37 `rules/docker-*.mk` and platform makefiles. Each of them changes in two places, and the second is the load-bearing one. Taking `rules/docker-lldp.mk`:

```diff
-$(DOCKER_LLDP)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_TRIXIE)
+$(DOCKER_LLDP)_LOAD_DOCKERS += $(DOCKER_CONFIG_ENGINE_RESOLUTE)
 ...
-SONIC_TRIXIE_DOCKERS += $(DOCKER_LLDP)
-SONIC_TRIXIE_DBG_DOCKERS += $(DOCKER_LLDP_DBG)
```

The top half repoints the base reference (`DOCKER_{CONFIG_ENGINE,BASE,SWSS_LAYER}_TRIXIE` becoming `…_RESOLUTE`, 140 added lines under `rules/` and `platform/` mention these three base variables (3 of those are the variable definitions themselves, 137 are references), and 108 of them sit on `_LOAD_DOCKERS`, `_DBG_DEPENDS` or `_DBG_IMAGE_PACKAGES`). The bottom half pulls the container out of trixie's registry, which is 37 deletions each of `SONIC_TRIXIE_DOCKERS` and `SONIC_TRIXIE_DBG_DOCKERS`.

Getting that order wrong is expensive. A reviewer proposed a suggestion that just added `filter-out $(SONIC_TRIXIE_DOCKERS)` in `slave.mk`. At that moment `SONIC_TRIXIE_DOCKERS` still held nearly every resolute container, so clicking "Commit suggestion" on it would have filtered every container out of the image. Deregister first, then filter.

Once the deregistration is done, `SONIC_TRIXIE_DOCKERS` still holds 18 regular registrations and 5 debug ones: trixie's own base chain (`DOCKER_BASE_TRIXIE`, `DOCKER_CONFIG_ENGINE_TRIXIE`, `DOCKER_SWSS_LAYER_TRIXIE`), the syncd and gbsyncd base templates, and an assortment of rpc / saiserver / PDE variants. That overlaps heavily with what 3.6 cuts from broadcom but is **not the same set** — the Marvell Prestera, Marvell Teralynx and Mellanox rpc/saiserver entries here have nothing to do with broadcom. What the two really share is that nothing in either has been validated on resolute.

The resolute-named base chain is three pieces, each with a `.mk`, a `.dep` and a `dockers/` directory: `docker-base-resolute` (`ARG BASE={{ prefix }}ubuntu:resolute`), `docker-config-engine-resolute`, and `docker-swss-layer-resolute`. 38 `.j2` files point their `ARG BASE` at these three variants; 36 of those are leaves and the other two are the config-engine and swss-layer inside the chain itself. That figure is not a count of modified files: 51 `.j2` files changed across the range, the rest for unrelated reasons.

Counting that number has a trap in it. A plain `grep -rl 'ARG BASE.*resolute' dockers/ platform/` returns 71, because the rendered `dockers/*/Dockerfile` files are sitting on disk too. Use `git grep` scoped to `.j2`.

On the platform side, `platform/template/docker-syncd-resolute.mk` and `docker-gbsyncd-resolute.mk` are new.

One silent trap in this layer: when copying a variant from trixie, the `docker_*_trixie_*` **variable names** inside the `.j2` have to be renamed to `_resolute_` as well. Missing one raises nothing; the template renders an empty value and the generated Dockerfile is quietly short a few lines.

### 3.3 Where packages come from

Packages whose procurement changed end up in one of three states. Packages whose procurement did not change are not in this list; the end of this section covers them.

**Install the ready-made Ubuntu deb** (moved into `SONIC_ONLINE_DEBS`, no source build): the grub2 family (`GRUB2_COMMON`, `GRUB_COMMON`, `GRUB_EFI`, `GRUB_PC_BIN`, `GRUB_EFI_AMD64{,_BIN}`, `GRUB_EFI_ARM64{,_BIN}`), the libnl3 family, the four kernel debs (`LINUX_HEADERS_COMMON`, `LINUX_IMAGE`, `LINUX_MODULES`, `LINUX_HEADERS`), plus `makedumpfile`, `rasdaemon` and `sedutil`.

**`dget` the Ubuntu source package, apply the SONiC patches, build it** (source build kept, only the upstream moved from Debian to Ubuntu): `bash`, `kdump-tools`, `libteam`, `libyang3`, `lldpd`, `lm-sensors`, `monit`, `openssh`, `socat`.

Three packages get filed here by reflex and none of them belong. `isc-dhcp` did get resolute build fixes, but `src/isc-dhcp/Makefile:13` still reads `dget -u http://deb.debian.org/...`: the source is still Debian's, it simply went back to SONiC's own version (see 4.4). `hsflowd`, `psample` and `libyang3-py3` do not use dget at all: `hsflowd` clones the sflow upstream and checks out a tag, `psample` clones Mellanox's libpsample, and `libyang3-py3` does `git clone --depth 1 -b v3.1.0` against CESNET's libyang-python. All three have resolute changes that are build fixes only.

**Unregistered from the build graph**: just `mpdecimal`, an orphan with no consumers. The files were not deleted — `rules/mpdecimal.mk`, `rules/mpdecimal.dep` and `src/mpdecimal/Makefile` are all still there, with only the `SONIC_MAKE_DEBS += $(LIBMPDECIMAL)` line at `rules/mpdecimal.mk:11` commented out. They are kept for the reason given at the start of 3.2.

grub2 going to online debs took several rounds to settle. A source build would have to build two source packages, because of the Ubuntu split, just to get `grub-efi-amd64-bin`, and there is no signing flow of our own to maintain.

The question that decided it was what patches SONiC actually applies to grub. The answer is two, and neither touches grub's functional code. `adjust-build-rules-for-debian.patch` only edits `debian/control` and `debian/rules`, so it is packaging-only and becomes moot once the source build goes away. `large-uid-skip-cpio-ustar.patch` only edits `tests/cpio_test.in`, skipping the `cpio_ustar` test when the uid exceeds 2097151, since the ustar format cannot represent a uid that large. So moving to the prebuilt deb loses no functionality. Both `.patch` files are still sitting in `src/grub2/patch/` today, undeleted, for the reason given at the start of 3.2.

One thing not to misread: the `grub-efi-amd64{,-bin}` we consume come from `src:grub2-unsigned` (see `rules/grub2.mk:35-38`), not from Ubuntu's signed packages. Signing is handled by a separate post-install flow, as `rules/grub2.mk:5-6` notes. Along the way we flip-flopped between 2.06 and 2.14 twice, 2.06 colliding with C23's `bool`/`false` keywords and 2.14 with overlayfs refusing to hard-link directories, before dropping the source build entirely.

libnl3 deserves a closer look, since it is the textbook answer to "why do we build this package ourselves at all". The only substantive reason is one symbol name: `rtnl_route_get_nh_id`, which upstream 3.12 calls `nhid`. Checked line by line, upstream 3.12 turns out to be a superset, not merely an equivalent — it also carries the `_DIFF(ROUTE_ATTR_NHID,…)` entry in `route_compare()` and the matching attribute-name table entry. What is actually needed is a two-line rename on the swss side. Someone said so at the time: change the swss source and you save building a whole package. That was right.

Two details about fetching the kernel from Launchpad are easy to lose. First, it has to be `ppa.launchpadcontent.net/.../pool/` directly; the `+files` style URL 302s to `launchpadlibrarian.net`, which is unreachable from the build environment. Second, Ubuntu's ABI string carries no arch (Debian's is `-amd64`), so `KVERSION` in `rules/linux-kernel.mk` is just `KVERSION_SHORT`:

```make
KERNEL_VERSION   = 7.0.0
KERNEL_ABISUFFIX = -1002
KERNEL_PKGVERSION = 7.0.0-1002.2
KVERSION ?= $(KVERSION_SHORT)
KERNEL_PPA_URL = https://ppa.launchpadcontent.net/canonical-kernel-team/bootstrap/ubuntu/pool/main/l/linux-sonic
```

The `-u` on `dget` is not laziness. On an Ubuntu slave the `.dsc` signer is an individual key that is in no available keyring, and installing `debian-keyring` does not help. Every Ubuntu-archive source build listed above carries it; of the 19 `dget` invocations across `src/**/Makefile` (`git grep -nE '^[[:space:]]*dget' -- 'src/**/Makefile'`), the only one without `-u` is `src/libnl3/Makefile:24`, and that file is dead code left behind by the move to an online deb.

Two mechanisms in this layer need watching.

`SPATH` in a `.dep` file must not be empty. The dependency hash is assembled in two places: each `rules/*.dep` expands its own file list with `git ls-files $(SPATH)`, and `Makefile.cache:650` then runs `git hash-object` over the result (`655` merely applies the rule template to each deb set). When the `.mk` provides no `SPATH`, `git ls-files` lists the entire repository, runs into the symlinks and gitlinks under `device/`, and `hash-object` dies. `grub2.dep` and `libnl3.dep` carry empty-SPATH guards for this reason. We managed to commit the same class of bug twice: de-forking `radius.mk` missed its `.dep`, so changes under `src/radius/pam` stopped invalidating the cache. `8c7b3b2aaf` restored the upstream form.

`SONIC_ONLINE_DEBS` install ordering is yours to arrange. It runs `dpkg -i` per deb, and without `_DEPENDS` you end up installing a `-dev` package before its runtime library, at which point dpkg aborts. libnl3 is how we found that out.

As for dbgsym: Ubuntu's debhelper hardcodes `DBGSYM_PACKAGE_TYPE` to `'ddeb'`. What we ended up with is a single-point patch of `Dh_Lib.pm` in the slave Dockerfile that puts it back to `.deb`. That patch is a little dirty (`grep -q ddeb && sed`, not idempotent) and only holds because the slave is always rebuilt from a fresh base. All the per-package `mv …-dbgsym_*.deb` band-aids that came before it are gone; they had also managed to break `PIPESTATUS`.

### 3.4 Submodules

16 submodule URLs in `.gitmodules` move from `sonic-net/*` to `canonical/*`, all over https rather than ssh. `platform/broadcom/saibcm-modules` additionally moves `branch` from `sdk-6.5.35-xgs` to `202605_resolute`. The gitlinks that differ turn out to be exactly the same 16:

```
platform/broadcom/saibcm-modules   platform/vpp
src/dhcprelay                      src/sonic-bmp
src/sonic-dash-api                 src/sonic-dash-ha
src/sonic-gnmi                     src/sonic-mgmt-common
src/sonic-mgmt-framework           src/sonic-sairedis
src/sonic-snmpagent                src/sonic-stp
src/sonic-swss                     src/sonic-swss-common
src/sonic-utilities                src/wpasupplicant/sonic-wpa-supplicant
```

`saibcm-modules` carries eight numbered adaptation **commits** (not `.patch` files — see 3.6 for the mechanism), `0001-resolute-kernel-abi` through `0008-resolute-changelog-timestamps`, the middle six being the Linux 7.0 work. The gitlink is nine commits ahead of `b9b38791bc` in total; the ninth is comment cleanup.

`src/sonic-frr/frr` is the exception. Its gitlink pins an upstream tag (`frr-10.5.4`) and the build applies 85 patches with `stg`. A dirty gitlink in the working tree is normal here; the makefiles do not consume that pointer.

This layer has the highest pitfall density in the project. The most dangerous of them drop changes silently; the rest do fail loudly, but rarely at the place that caused the problem.

The most expensive: when a submodule branch does not follow the superproject's rebase, upstream fixes disappear without a sound. The healthy state is "submodule branch = upstream + our patches, strictly fast-forwardable". Once that diverges, a superproject rebase hitting a gitlink conflict forces us to keep our own commit, upstream's fix stays outside, and nothing anywhere reports it. "Every SAI counter reads zero" came from exactly this: `sonic-sairedis` was missing one upstream commit whose title said, in so many words, that it made counters work on Broadcom platforms. After finding it we wrote `scripts/submodule-ff-audit.sh` and now run it after every upstream sync. `sonic-utilities` was in the same divergent state at the time and had already lost two real fixes.

The rest:

A submodule's **local** branch name is not its remote branch name. Locally they are `resolute` or `202605`; only the remote is called `202605_resolute`.

The canonical URLs in `.gitmodules` have to be https. With ssh, any environment without a key simply cannot clone. And that file has to be edited **in place**: append a new section and the one missing `path =` is an orphan while the original section still applies, so it looks changed and is not.

Clones made with `--reference` become unusable once their alternates disappear. Lose them and `mgmt-framework`, `swss` and `sairedis` end up missing blobs. The fix is deinit, `rm -rf .git/modules/<name>`, and re-clone from origin; note the submodule git dir may be exactly `.git/modules/<name>`, with no `src/` prefix. Separately, the alternates are not mounted inside the docker build container, which produces `unable to normalize alternate object path` and a fatal 128 in the step that reads the commit label. That one is non-fatal, since the step is best-effort in SONiC, and it costs only the image's git label.

A superproject rebase gets interrupted by untracked build residue, and after that failure `--continue` reports a phantom conflict (`git ls-files -u` is actually empty). The reliable route is to rebase in a clean temporary worktree and then `reset --hard` the branch onto the result, leaving the main tree's residue where it was.

`AGENTS.md` records a few rules, the least intuitive being that gitlink reachability has **three** states (upstream commit with upstream URL / Canonical commit already pushed to canonical / Canonical commit never pushed) and that the URL alone cannot tell you which. There is also a hard one: a submodule's Canonical commits go only to `canonical/<sub>:202605_resolute`, never to `sonic-net`.

### 3.5 The target rootfs

A thin layer: a few version strings and package names in `build_debian.sh`, plus one decision about FIPS.

```diff
-DOCKER_VERSION=5:28.5.2-1~debian.13~$IMAGE_DISTRO
-CONTAINERD_IO_VERSION=1.7.28-2~debian.13~$IMAGE_DISTRO
-LINUX_KERNEL_VERSION=6.12.41+deb13
+DOCKER_VERSION=5:29.6.1-1~ubuntu.26.04~$IMAGE_DISTRO
+CONTAINERD_IO_VERSION=2.2.5-1~ubuntu.26.04~$IMAGE_DISTRO
+LINUX_KERNEL_VERSION=7.0.0-1002-sonic
```

The kernel install takes one more deb: `linux-modules-*` has to go in alongside `linux-image-*`. docker's GPG key and apt source move from `linux/debian` to `linux/ubuntu`. The firmware packages `firmware-linux-nonfree` and `firmware-intel-misc` do not exist on Ubuntu, so that becomes `linux-firmware`. The line originally ended in `|| true` on the grounds that vs needs no real firmware; `484cf5330b` removed it, since `linux-firmware` does exist in the resolute archive and a failure there should be an error rather than a silent skip. And the `resolvconf` dependency line is deleted; 3.7 explains why.

**FIPS is off on resolute**, and hard off. `rules/config:381` now reads `INCLUDE_FIPS ?= n`, and `rules/sonic-fips.mk` adds a guard:

```make
ifeq ($(BLDENV) $(INCLUDE_FIPS), resolute y)
$(error INCLUDE_FIPS=y is not supported on resolute)
endif
```

That is `d314b3b91f`. The road before it is worth recording, because it looked entirely reasonable: the FIPS mirror publishes no `fips/resolute/` tree, so the original approach reused trixie's binaries (same t64 ABI) with a `FIPS_DOWNLOAD_BLDENV = trixie` pointing downloads back at `fips/trixie/`. What killed it was not ABI but **version**: several of trixie's FIPS binaries are older than what resolute itself ships, most glaringly python3.13 and libpython3.13 against a resolute rootfs that has no 3.13 at all. Since nothing had ever been tested with FIPS on, the answer was to take Ubuntu's own openssl, openssh, python and golang instead. The resolute arms in `sonic-fips.mk` came out too; only trixie's remain.

One knock-on: golang in the slave moved from following `golang-go` to pinning `golang-1.24-go`, because `golang-go` on resolute is go 1.26. That also frees the Dockerfile arm from the `FIPS_*` variables, which are now undefined for resolute.

`installer/default_platform.conf` holds the ONIE installer's grub.cfg kernel path.

`scripts/build_debian_base_system.sh` has been cleaned up twice recently. `943eae7337` deleted the `if [ "$IMAGE_DISTRO" == "resolute" ]` branches: with only resolute supported, debootstrap points unconditionally at `archive.ubuntu.com/ubuntu`, and the apt-list cache path likewise needs no per-distro fork. `d5f53658df` switched the snapshot source from `packages.trafficmanager.net/snapshot` — a mirror of Debian's snapshot service — to `snapshot.ubuntu.com`, which actually covers resolute. Both are the principle from 3.2 applied in the positive direction: once trixie compatibility is no longer required, the conditional branches themselves become diff you can delete.

### 3.6 broadcom (dell / XGS)

The first decision in this layer was a scoping one rather than a technical one: restrict the work to dell and XGS. `platform/broadcom/rules.mk` therefore comments out the DNX/Jericho and legacy Tomahawk SAI, the kmods for eight vendors (nokia, arista, nexthop, accton, cel, supermicro, ufispace, micas, with dell retained), the rpc, saiserver and PDE containers, and `one-aboot.mk` — Arista's Aboot image, which would also drag the dropped machines back in via `DEPENDENT_MACHINE`.

The reasoning: dell is the only platform validated on real hardware running Ubuntu 26.04. Leaving unvalidated vendor kmods in the build graph means every kernel bump comes with a pile of code to fix that nobody can test.

The Linux 7.0 adaptation splits three ways, according to who owns the source.

**Sources fetched at build time** (dget or clone) get a `.patch` overlay, because that tree is recreated on every build and edits to it would not survive.

**Submodules we control** get direct commits on the submodule branch, followed by a gitlink bump in the parent. `saibcm-modules` works this way: its eight numbered items are **git commits**, not `.patch` files — `git ls-files '*.patch'` returns nothing in that submodule, and `b9b38791bc..d4519fdeee` edits `debian/rules`, `make/Makefile.linux-kmodule`, a few `lkm.h` headers and other source and packaging files directly.

**In-tree sources** get edited directly, not through sed or awk: `platform/broadcom/sonic-platform-modules-dell/**/*.c` (four copies of `mc24lc64t.c`, plus `cls-i2c-mux-pca954x.c` and `fpga_gpio.c`), `sswsyncd/debian/rules`, and `platform/pddf/i2c/**`. This matches upstream's own habit: all eleven upstream `.patch`/`series` files live under `src/` in fetched packages, and none sit alongside in-tree source.

A few pitfalls here.

`BUILD_SKIP_TEST` does not cover debhelper's test phase. Skipping a vendor's tests takes an explicit `override_dh_auto_test` in that vendor's own `debian/rules`.

`opennsl-dnx`'s header symlinks are not idempotent: `debian/rules` guards with `[ ! -e ]`, and `-e` is **false for a dangling symlink**, so the `ln` runs anyway, collides with the existing link, and a from-scratch build reports `ln: Already exists`. The fix at the time was `ln -sfn`, folded into an overlay patch. That state has since been reverted, though: `c57035d7e8` deleted the whole DNX overlay when the scope narrowed to dell/XGS, so the patch does not exist in the final tree. It is kept here because non-idempotent guards of this shape resurface elsewhere.

`sdklt`'s `clean` target has a `-j16` race. The race objects are the `sdklt/linux/*/generated/` directories, and `dpkg-buildpackage -j16` recursing into them can hang; note `debian/rules clean` also runs during a from-scratch build. But the race is intermittent. On a genuinely clean tree the `clean` target still runs, there is simply nothing generated yet to race over; on a dpkg cache hit the vendor's `clean` is never entered at all. The 08-23 rebuild did not reproduce it. The accurate statement is "not reproduced this round", not "fixed": the tree really has neither `-j1` nor `.NOTPARALLEL`, and the fallback is `SONIC_CONFIG_MAKE_JOBS=1` on the command line.

One practical note: in a multi-variant build the primary bin finishes first, and `sonic-broadcom.bin` self-checks via `payload_sha1`. Once it is done, a transient network failure in a dependent variant does not invalidate it.

### 3.7 Runtime

All three changes in this layer built entirely green and only surfaced as dead functionality once deployed onto real hardware, which makes them the hardest class to anticipate here: the build system gives no signal at all. (That audit found four defects in total. The fourth, every SAI counter reading zero, traced to a stale submodule gitlink and so belongs to 3.4.)

On this image SONiC's event framework was mute. The cause is that Ubuntu's `rsyslog` ships an enforced AppArmor profile and Debian's does not. Every `omprog` call into `/usr/bin/rsyslog_plugin` came back EACCES, so the plugin process never started and no action in `/etc/rsyslog.d/*_events.conf` could emit anything. The fix is a profile override that `build_debian.sh` copies into `/etc/apparmor.d/local/`:

```
/usr/bin/rsyslog_plugin ix,
capability chown,
/etc/sonic/** r,
/var/run/redis/** r,
/usr/share/sonic/** r,
```

`ix` lets the plugin execute under the same profile, and `capability chown` is there because rsyslog applies `$FileOwner` and `$FileGroup` to the log files it creates.

This is not the only AppArmor trap of its kind. `comm="hostname"` gets denied `file_inherit` and `open` on `/var/lib/dhcp/dhclient.eth0.leases`, because Ubuntu ships an enforced `/etc/apparmor.d/hostname` that does not exist among the 107 profiles in the official Debian image. Next time some helper fails without a word, check AppArmor first.

The switch had no DNS at all. The cause here is four layers deeper than "the package is missing", so here it is in full.

There is no real `resolvconf` package in the Ubuntu archive; `systemd-resolved` declares `Provides/Replaces/Conflicts: resolvconf` and owns the name. So the upstream `apt-get install resolvconf` line (`ba3fb8d5f5:build_debian.sh:381`, deleted in the final tree) *succeeds* on Ubuntu, it just installs resolved. That is the first layer.

`/sbin/resolvconf` therefore ends up a compatibility symlink to `resolvectl`. It supports `-a` and `-d`, but not the `--disable-updates`, `--enable-updates` and `-u` that SONiC uses, and there is no `/run/resolvconf/interface`. That is the second layer.

The third is more fundamental: `resolvectl(1)` states outright that its resolvconf compatibility mode only updates `/etc/resolv.conf` when that file is a symlink to `/run/systemd/resolve/resolv.conf`, and SONiC keeps it a static file. So even papering over the first two layers, the leased DNS servers would never reach the glibc resolver.

The fourth is functional: SONiC's `DNS_OPTIONS` (`search`, `ndots`, `timeout`) have no equivalent at all in `resolved.conf`, which only has `DNS=`, `Domains=`, `Cache=` and `ResolveUnicastSingleLabel=`. Going resolved-native silently drops that feature.

So the conclusion is to render `/etc/resolv.conf` directly. The new `files/image_config/resolv-config/dhclient-enter-hook` overrides `make_resolv_conf()`, assembles the `search` and `nameserver` lines itself, appends `%interface` scope to link-local addresses, and honours a `/run/sonic-resolv-static` marker so static DNS configuration wins. Alongside it, `resolv-config.sh` learned to clear stale nameservers when static DNS configuration is removed, and the `resolvconf --*-updates` calls in `interfaces-config.sh` are gone.

This is not a way around systemd-resolved. "The application writes `/etc/resolv.conf` itself" is one of the four modes resolved officially supports, and resolved steps back into being a consumer on its own. And on the actual machine `nsswitch.conf` is `hosts: files dns` (no `resolve`), so glibc was already reading `/etc/resolv.conf` through nss-dns and resolved was never on the query path.

`aaastatsd` crashed on every timer tick. After de-forking to Ubuntu's ready-made `libpam-radius-auth 3.0.0-1build1`, the `/etc/pam_radius_auth.d/statistics/` directory it inotify-watches was gone. That directory comes from the `.list` of SONiC's self-built `1.4.1-1`, and the newer Ubuntu package does not ship it. Digging further turned up something worse: Debian's 1.4.1 carries four quilt patches (chap, peap-mschapv2, nas-ip-address, fix-blastradius), and on 3.0.0 `protocol=chap` and `protocol=mschapv2` are silently ignored and fall back to PAP, so authentication just fails against a server that wants CHAP or MSCHAPv2. The de-fork was reverted (`d605df6b58`) and the `.dep` file restored (`8c7b3b2aaf`).

Besides those three there is `DEV | default("")` in `database_config.json.j2` (with an explanatory comment), and compile fixes in `src/sonic-eventd/rsyslog_plugin/timestamp_formatter.cpp` and `src/systemd-sonic-generator`.

One thing we chased for a while and confirmed is *not* ours: `dmesg.service` keeps `show system-health sysready-status` permanently red. That unit is Ubuntu-only, `Type=idle` with no `RemainAfterExit`, so it goes inactive seconds after finishing. Harmless, but tests waiting on sysready time out. Upstream sonic-net's own images are red too, so it is not a resolute regression.

---

## 4. Pitfalls

### 4.1 exit 0 lies

The most expensive one was frr. The Jul 24 deb built fine: exit 0, all three debs present. Deployed to dut02, BGP would not come up. We spent a while on the configuration first. The configuration was fine; the deb was missing `dplane_fpm_sonic.so`.

The old Makefile patched with dget+quilt, and the line read:

```
QUILT_PATCHES=../patch quilt push -a || true
```

Patch 0012 modifies `zebra/subdir.am`. On the Ubuntu FRR source that hunk does not apply, quilt failed, and `|| true` ate the failure. `subdir.am` never got the module rule, so the module was never compiled at all.

The second safety net leaked as well. That line in `frr.install` is a glob, `dh_install` does not default to `--fail-missing`, and a glob matching nothing is silently skipped. So the deb packaged up successfully, just one `.so` short.

The current Makefile uses stg, and `src/sonic-frr/Makefile` carries `.SHELLFLAGS += -e` so a patch failure aborts the build. After a cache-off rebuild the module appeared, and on deployment BGP came up on v4 and v6 with 215 routes programmed end to end. A successful exit status therefore guarantees nothing in a SONiC build. Inspect the package contents.

Two other packages produce an incomplete build for unrelated reasons. `lm-sensors`'s `PROG_EXTRA=sensord` is a functional out-of-tree variable, so dropping it still builds, `sensord` just does not exist, and `docker-platform-monitor` wants it; comparing package contents with `dpkg -c` catches that one. `librrd-dev` is a different failure: a Build-Depends the stock `debian/control` omits, which compiled locally the whole time only because the slave image had it preinstalled. `dpkg -c` cannot catch that at all — it inspects outputs, not declared inputs — and only a build in an environment holding just the declared dependencies will surface it.

One latent risk remains: the vendor include in the slave Dockerfile carries `ignore missing`, and `files/sonic-slave-Dockerfile.vendor.j2` does not exist in the tree. It has no consumers today. But move something like the dbgsym patch into it and the failure shows up as an inexplicable `mv …-dbgsym_*.deb` error in some src package, and nobody will think to go looking for a file that is not there.

The last two are the build graph eating things by itself. One is a container dropped by `filter-out`: edit one of the sets from 3.2 wrongly and a container quietly stays out of the image while the build exits 0. Two checks catch it without a deployment — compare `repositories.json` inside `dockerfs.tar.gz` against the `init_cfg` FEATURE table, or compare the enabled container systemd services against the images actually burned in — but do not try to verify by querying `slave.mk` variables, since parsing `slave.mk` on the host is extremely slow and tends to hang. The other is a stale gitlink dropping an upstream fix, mechanism in 3.4. That one is the worst of the class because it does not lose something once: as long as the divergence stands, every subsequent upstream fix is blocked too.

### 4.2 The error points somewhere other than the cause

bash fails to build with `Could not open bash.pdf`, which looks like a docs build or a patch problem. It is the *host's* AppArmor `gs` profile, in enforce mode, refusing to create files in the build directory. The fix is a host-side `local/gs` override; not one line changes in the repository. This one was once misattributed to fakeroot's "payload not recognized". That message is real, but it is secondary IPC noise, not the cause.

`wget` in the slave image downloads nothing and later steps come up short, which looks like a network problem. The cause is `SONIC_VERSION_CACHE` being enabled, which makes the wget in the slave Dockerfile silently skip. Hence `SONIC_VERSION_CACHE_METHOD = none` pinned in `config.user`.

redis reporting "0 routes" had us suspecting fpmsyncd or orchagent was not working. The cause was ssh quote escaping leaving the `--scan --pattern` glob unexpanded, making the counts an artifact. A clean `keys` query gives 209 entries in APPL_DB's ROUTE_TABLE and 215 in ASIC_DB's ROUTE_ENTRY. The same trap showed up once on a port count (`PORT:1`). The real lesson is about quoted queries over remote execution: verify one locally before believing its output.

TD3 reporting `CIH: LOAD FAILED` was attributed in a previous round to "platform-modules 1.8.1 being too old", which was wrong. `libsaibcm` registers 156 `/etc/bcm/flex/**/*.pkg` files as dpkg conffiles, and an upgrade does not clear out old files still treated as preserved conffiles. So installing SAI 15.2 leaves the old `b870.6.4.1/` directory in place, `config.bcm` still points at it explicitly, and the new SDK loads the old CANCUN.

`show ip …` saying "No such command" and `show.plugins.*` warning about hyphen imports are neither of them resolute regressions. The first is a database that is not ready or a missing minigraph; the second is an upstream bug, since `import_module` rejects hyphens. Also, inspecting the vs rootfs means looking at `image-*/fs.squashfs` in the qcow2's third partition, not the intermediate `target/*.squashfs`. Opening the wrong file leads to the wrong conclusion that squashfs dropped files.

flashrom reporting `No chipset found` on the dut looked for a while like us having lost Dell's patch. It is unrelated to that patch: the cause is the kernel's `spi_intel.writeable=0`, while the descriptor itself already permits writes. And that patch worked through an SMI backdoor, sending commands to port 0xB2 so Dell's BIOS SMM did the write on its behalf. As for whether anything still uses the package: within this superproject, `flashrom` appears only in packaging positions (`rules/flashrom.*`, `src/flashrom/`, the version manifests, `sonic_debian_extension.j2`) and there is not one functional call site. (It is a source build again now, per 4.4; that does not change the caller situation.) An earlier audit reported that the callers in `sonic-platform-common` and the vendor platform repositories are all `return False` stubs by now; that part was not re-checked this round, so do not treat it as settled.

Diffs in unrelated files like `device/arista` showing up on the PR page are not somebody editing them quietly; it is a display artifact of a stale GitHub merge base. Diagnose by comparing the PR's `base.sha` against the true `merge-base`. Raise it with the reviewer proactively, or they will read those phantom entries as changes this branch actually made.

### 4.3 Only a from-scratch build exposes these

A cache-warm build hides all of the following.

These three were forced out by the two from-scratch builds in July (all three fixes carry an author date of 2026-07-21); by 08-23 they were already in the tree and that run only re-verified them. The local `sudo` in the KVM step strips the environment, so `SONIC_USERNAME` and `PASSWD` never reach `scripts/build_kvm_image.sh`, which reads both at its line 140. The fix is an explicit `sudo -E env VAR=val …`, landed in `33862dc91c`. Note that `build_image.sh:51` already carries the fixed form, so the bug is not visible at that line today. `opennsl-dnx`'s header symlinks are not idempotent (mechanism in 3.6). And `dash-engine` runs into PEP 668, since its base is an external image that does not inherit our `pip.conf`.

The empty `SPATH` in a `.dep` (mechanism in 3.3) belongs to the same batch, from the 07-23 online-deb build.

Two more are matters of procedure rather than defects. To confirm a particular deb really was rebuilt without clearing the cache first, pass `SONIC_DPKG_CACHE_METHOD=none` for that run; the `rwcache` setting in `config.user` will otherwise restore the cached deb (chapter 1 covers how to wipe properly). And the `sdklt` race never enters the vendor's `clean` on a cache hit, so "it did not hang this round" is not "it is fixed".

One phenomenon that is easy to misread: a single vs run rewrites 19 `.flags` stamps from `broadcom` to `vs`, while the debs and logs themselves are untouched. Using `.flags` to decide which platform built a deb will mislead you.

### 4.4 Roads taken and abandoned

boost was adapted to 1.88 across a full round, then reverted to 1.83 (`aae7dd2ae0`). Reasoning in chapter 2.

grub2 flip-flopped between 2.06 and 2.14 twice before the source build was dropped entirely. Reasoning in 3.3.

dbgsym went through three approaches: per-package `mv` band-aids, `noautodbgsym`, and `DEB_BUILD_OPTIONS=dbgsym`. All withdrawn (`001f038067`) in favour of the single-point `Dh_Lib.pm` patch (`d5647e2ef2`).

force-depends was initially passed via `_DEB_INSTALL_OPTS`, which misused sudo's option position. Reverted in `5c6c5909fc`, and it now lives at `slave.mk:1015`.

Five packages were de-forked and then went back to source builds, each for a different reason. `lldpd` cannot lose patch 0001 (next section). `libpam-radius-auth` needs four quilt patches and the PAM options (3.7). `isc-dhcp` went back to the SONiC version while keeping the resolute build fixes. `initramfs-tools` reverted the de-fork but kept upstream's two separate patches rather than one merged patch. `flashrom` went back to a 0.9.7 source build (`e3f210bccd`), and its reason differs from the other four: not that a patch could not be lost — quite the opposite, the Denverton patch has no live callers by the analysis in 4.2 — but to **bring the diff to zero**, which is the principle from 3.2. Literally to zero: `rules/flashrom.mk` and `rules/flashrom.dep` are now byte-identical to the baseline and the package has left the diff entirely. That is part of why the final file count went from 214 to 213, the other part being `rules/config` joining it. After the revert, `/usr/local/sbin/flashrom` was checked for the `DENVERTON` and `DENVERTON SBASE` symbols, confirming patch 0002 is compiled in rather than merely applied.

`iproute2` is often counted as a fifth case and should not be. Relative to the baseline it is byte-for-byte unchanged: `rules/iproute2.mk` is still wrapped entirely in `ifeq ($(BLDENV),trixie)`, and `src/iproute2/Makefile:11` still dgets from `deb.debian.org`. What `e6067ede11` removed was the resolute-specific source build we had added mid-way, which restored the upstream trixie-gated form — the file and its Debian source are untouched, resolute simply does not build it. On resolute the stock Ubuntu apt package is used instead, which is where the suspended EVPN MH patch in chapter 6 comes from.

The broadcom narrowing overshot once. The four gbsyncd components that `platform/broadcom/rules.mk` includes under `INCLUDE_GBSYNCD` have to stay; `a133e5d573` put them back.

py3.14 removed `pkgutil.get_loader`, and we first patched around it with sed. Once upstream `sonic-utilities` fixed it properly the patch was deleted (`6744948bc8`) in favour of a gitlink bump.

One commit was dropped on purpose: our own `--break-system-packages` plus `pin ==1.4.0` on `docker-dash-engine`. Upstream #28587 happened to add `--break-system-packages` as well, with an old-base fallback, and after merging that ours became an empty commit. We threw it away rather than leave "added a pin, then removed the pin" noise in the history. That file is now byte-identical to `sonic-net/202605`.

### 4.5 Deciding whether a package can be de-forked

"An upstream distro has a package with that name" is not sufficient grounds. These are the rules that crystallized after getting it wrong.

Look at the patch delta and at the options SONiC actually uses, because going by package name produces wrong answers. Debian's `libpam-radius-auth` 1.4.1 carries four quilt patches. `lldpd`'s `0001-return-error-when-port-does-not-exist` determines the return semantics of `lldpcli`: without it, `lldpcli` returns success when the port is missing, `lldpmgrd` marks the work done and drops it, and the result is that the port's LLDP port-id and description are never configured, with no error anywhere. That is why lldpd went back to a source build (`6742869eb9`).

Comments lie, and these were ours. Both `rules/lldpd.mk` and `rules/flashrom.mk` once claimed "all SONiC patches upstreamed"; both claims were false and both lines were added on this branch. Each package later went back to a source build (`6742869eb9` and `e3f210bccd`) and the false comment went with it: `rules/lldpd.mk` now states accurately that patch 0001 is not upstream in 1.0.19, and `rules/flashrom.mk` is back to the baseline `# flashrom package`.

The lesson is not that the comments got fixed but how they were written in the first place: during the de-fork someone wrote "the patches are all upstream" without checking the patch contents. Check the patches, not the comments.

Take the baseline from the production branch, not a PR branch. On `canonical/202605_resolute`, `lldpd` has always been a Debian 1.0.16 source build; the de-fork never landed in production. So the real net delta is "Debian 1.0.16 source build to Ubuntu 1.0.19 source build", not "from an online deb back to a source build". We got this wrong once and nearly wrote it into a commit message.

`SONIC_MAKE_DEBS` is a registry of build methods, not an unconditional build list. What actually triggers a build is the final target (`sonic-vs.bin`), the docker `_DEPENDS` chain, and dependency propagation. A package with no consumer never gets triggered even when registered. That is the basis for judging `mpdecimal` an orphan and pulling it out of the build graph; the files themselves stay (see 3.3).

Do not put the intermediate state and the final state in one de-fork commit. `07f2c3c116`, `10047cb0e0` and `84ea013156` each combine "switch src to Ubuntu dget" with "switch to an online deb", so reverting leaves a half-cooked `src/` tree behind.

### 4.6 Repository operations and review

The most damaging mistake in this area is working in the wrong directory. When commands are driven by automation each one may start from the default working directory, so a previous `cd` does not necessarily still apply and the cwd silently reverts to `~/sonic-buildimage`, the docs repository. This has bitten twice in practice. Once an entire `MAKEFILE_LIST` analysis ran against the wrong repository and had to be thrown away. Worse, once a `git commit --amend` landed in the docs repository and overwrote a docs commit's message with lldpd wording. There was also an occasion where a cleanup ran in the wrong repository.

The rule is simple: every git write operation spells out `git -C <repo>` rather than relying on a previous command's `cd`.

The two repositories must not contaminate each other either. `~/sonic-buildimage` is upstream plus a `docs/`; `~/sonic-buildimage-resolute` has no `docs/` at all. That convention got tangled once, when `202605_resolute_doc_fix` picked up development content, and untangling it was tedious.

On diff hygiene, the following came back repeatedly in review.

Whether a file ends in a newline has to match upstream. `29dd3fa2fa` was a dedicated pass restoring upstream's EOF bytes.

Do not regenerate a patch just to tidy up its line numbers. The reviewer's words: newline formatting, optional line-number changes, the patch generator's trailer — keep them as they were; a few more offsets is all it costs.

Keep the original patch application mode, quilt or stg, unless that mode is genuinely inappropriate.

Do not abandon existing variables, such as `LLDPD_VERSION_SUFFIX`.

For things like `ifeq`, where you can avoid a diff, do not add indentation.

Deleting a file is sometimes noisier than keeping it. This is the review-side face of the principle in 3.2: leaving the no-longer-used grub2 and libnl3 files in place produces a smaller diff than removing them.

When a PR split goes wrong, the cause is overlapping logic rather than overlapping files. One logical change scattered across several PRs because it happened to be line-level is far harder to spot than two PRs touching the same file.

`canonical/202605_resolute` is the production branch and direct pushes are forbidden; changes land through PRs. There have been three one-off, explicitly agreed exceptions (a re-push on 2026-07-23, a fast-forward on 07-28, and the 08-17 reset onto the true merge-base `ba3fb8d5f5`), frozen since. The rule covers the superproject only, not the submodules.

---

## 5. The three branches

Everything below refers to the **canonical remotes**; the local copies of these branches are the stale 07-27 versions (see the end of this section):

```
sonic-net/202605 ──● ba3fb8d5f5  (shared merge-base, and where canonical/202605_resolute still points)
                   │
                   ├── 202605_resolute_mech  fd5781e4d2   2 commits   105 files  +1526 −234  → PR #7 (1/2)
                   │      └── 202605_resolute_real  c139d173e7  +11 = 13 commits  212 files  +2664 −823  → PR #8 (2/2)
                   │
                   └── 202605_resolute_sheldon  648c8121aa  190 commits  213 files  +2699 −823  ← the final state is here
```

`_mech` is an ancestor of `_real`. But `_sheldon` and `_real` are not ancestors of each other: `_sheldon` is the organic development history and `_real` is its reorganized form.

**In content the two are now level.** `canonical/202605_resolute_real` differs from `_sheldon` by exactly **one file** and `+35` lines: `rules/config.user`, which by convention should not be on a formal branch anyway (see 3.1). `_real` is therefore the complete formal version of `_sheldon`, with no delta left to fold.

That is the result of the 08-26 redo. Before it, `_real` still held the content from the reorganization and trailed `_sheldon` by 60 files, and "fold the delta back into `_real`" was the number one outstanding task. It is done.

One trap: **the local `202605_resolute_mech` and `_real` are the 07-27 versions and are obsolete.** The two `_real` heads have diverged 13 and 13 (local `d3125f835f` against remote `c139d173e7`) — same subjects in the same order, entirely different hashes, because the whole stack was rebuilt on 08-26. Read and edit the `canonical/` copies; the local pair is uncleaned residue.

`_mech` is two commits because of a hard review requirement: copy first, rename second. The first commit, `4fe94aa35a`, copies the slave and docker-layer variants from trixie verbatim — pure additions, and a reviewer can skip straight past it. The second, `fd5781e4d2`, does a pure `s/trixie/resolute/` over those copied files plus the base-image switch.

Done the other way round, with one commit that both creates files and changes their content, the reviewer faces 105 wholly-new files and cannot tell which parts are a copy and which are a real change. The review comment at the time was exactly that: go back to the copy-then-modify pattern, otherwise this cannot be reviewed.

There is a companion trap in the criterion: "purely mechanical" is not "blind global replace". Tokens that point at genuine Debian artifacts are preserved on purpose: the `~trixie` suffix in docker-ce version strings, `DEBIAN_VERSION` where it really does mean the Debian version, and at the time the `fips/trixie` download path (that one has since gone along with FIPS being switched off, see 3.5, but the call was right then). There were also names that should have been renamed and were not, such as the variable `DOCKER_BASE_TRIXIE`. It has to be checked file by file rather than with one sed.

`_real`'s 11 thematic commits:

```
5c6067e921  adapt the sonic-slave build environment to Ubuntu 26.04
0850b30d04  wire BLDENV=resolute into the build graph
6a62473241  bootstrap the target rootfs on Ubuntu 26.04
54213c56c8  retarget and sync the build-consumed submodules
acb1c7c4ff  procure the kernel, grub2 and libnl3 from Ubuntu archives
d4042c7eb8  fix src package builds for the Ubuntu 26.04 toolchain
530a4fdbf1  broadcom: dell/XGS Linux 7.0 kmod adaptation
011ce882a7  comment hygiene across the resolute changes
739cfc65cd  de-fork src packages to Ubuntu sources
04b35e5415  let rsyslogd run the SONiC event plugin under AppArmor
c139d173e7  render /etc/resolv.conf directly instead of via resolvconf
```

Splitting by theme rather than by layer lets a reviewer look at one thing at a time. The themes map many-to-many onto this document's layers: `d4042c7eb8` alone touches `dockers/`, `rules/`, `src/bash`, `src/isc-dhcp` and `platform/broadcom`, spanning 3.2, 3.3 and 3.6.

---

## 6. Not finished

None of this blocks building either `.bin`, but whoever picks it up should know.

Hardware validation covers exactly **one** unit. The physical device the broadcom image has booted on is a single Dell S5232F. No second unit of the same model has been tried, let alone a different model. It goes first here so that "validated on real hardware" earlier in the document is not read as more than it is.

iproute2's EVPN MH `bridge-fdb` patch is suspended. `docker-base-resolute.mk` uses stock Ubuntu iproute2, while the self-built version that carries the patch is now built only under trixie, with a "restore `_DEPENDS` if needed" comment left behind. The cost is that MACs learned via the control plane cannot be told apart from data-plane ones, which is what the Cisco-contributed patch was for.

`docker-base-resolute.mk` still opens with "based on Debian Trixie", left over from copy-then-rename. By the principle in 3.2, a comment with no functional value that is also wrong costs less to revert than to keep — note this is the opposite case from keeping the grub2 patch files, which are correct and simply unused. (Its twin in `rules/flashrom.mk` is already gone, having left with the return to a source build.)

`sdklt`'s `-j16` clean race is not fixed in-tree. The 08-23 run never triggered it, so no job count was lowered there; the fallback if you do hit it is `SONIC_CONFIG_MAKE_JOBS=1` on the command line.

The `Dh_Lib.pm` dbgsym patch is not idempotent (`grep -q ddeb && sed`) and only holds because the slave is always rebuilt from a fresh base. And the base is not pinned: `sonic-slave-resolute/Dockerfile.j2` uses the floating `ubuntu:resolute` tag, and `debhelper` is an unversioned apt install at line 287. An upstream debhelper change could make the patch stop matching, which is exactly the kind of thing a from-scratch build would surface.

Everything cut from broadcom has no build coverage on resolute: DNX, legacy-TH, rpc / saiserver / PDE / one-aboot, and the eight vendor kmods we commented out. One count worth stating precisely, since two different numbers circulate: `rules.mk` carries 20 `platform-modules-*` includes, and exactly one (dell) is enabled today. We disabled eight of them; the other eleven were already disabled upstream.

TD3's CANCUN config.bcm points at an old version. 23 upstream TD3 configuration files point at `b870.6.4.1` (19 `*.config.bcm` plus 4 `config.bcm.j2` templates) while SAI 15.2 ships only 6.15.0, and because those old files are still treated by dpkg as conffiles they are not cleared out on upgrade, so installing the new one loads the old CANCUN. The fix is to use `default/` and delete the `/usr/lib/cancun` line.

**resolute's supported scope is amd64.** The `armhf` branch at `rules/linux-kernel.mk:12-14` is inherited from upstream untouched, no non-amd64 target has ever been tried, and the Launchpad `linux-sonic` feed has nothing for one. By the principle in 3.2 it stays exactly as it is: it never reaches the image and changing it buys no functionality. It is listed here to define the scope, not as a task.

In-place upgrade is undefined. The TD3 CANCUN failure in 4.2 is itself an in-place-upgrade failure mode (conffiles surviving an SAI package bump), which shows upgrade paths do get exercised. Yet whether upgrading a trixie-based image in place to resolute is a goal, is tested, or is explicitly unsupported has never been written down. Whoever takes this over needs to decide, otherwise there is no way to know whether to test upgrades for other packages.

Broadcom's SAI trio has to be swapped as a matched set. Replacing `libsaibcm` alone breaks the switching plane, which happened on 2026-07-25; recovering from it also turned up that leftover hostif state can only be cleared by a reboot.

Where the PPA work should live is undecided. The scaffolding plus the first three packages are done on `202605_resolute_ppa`, with no PR opened and no target PPA chosen. The branch state is worth stating precisely: 40 commits relative to its own merge-base, but **40 ahead and 14 behind** `_sheldon`. It is missing the last fourteen commits of the final state — a number that grows as `_sheldon` advances; it was five on 08-23 — so rebase or fold it before building on it.

---

## 7. Three things to do first

**Move PR #7 and #8 through review.** The fold was completed on 08-26 (chapter 5), so `_real` is the formal version of `_sheldon` and both PRs now carry current content. What is left is the review itself, and then merging into the production branch `canonical/202605_resolute` — which still points at the baseline `ba3fb8d5f5`, meaning not one line of this port has reached production yet. While you are there, delete the stale 07-27 local `_mech` and `_real` so nobody works against the wrong branch again.

**Decide the iproute2 EVPN MH patch one way or the other** (background in chapter 6). Either restore the self-built iproute2 and bring the patch back, or record the feature as dropped. An "if needed" comment is not a decision.

**Extend broadcom coverage, or write down that it will not be extended** (chapter 6 has the inventory). Supporting a second platform means taking the eight commented-out vendor kmods through the Linux 7.0 adaptation one by one; 3.6 gives a sense of the volume.

One entry point, so nobody has to reassemble the invocation from fragments scattered through this document. The full procedure is in `specs/2026-07-21-resolute-clean-rebuild-design-en.md` in this directory, covering docker image cleanup, `docker builder prune -af`, and the shared dpkg cache as well. What follows is the spine only: `make reset` by itself does not clear `/var/cache/sonic/artifacts`, docker images, or the builder cache.

```
# reset does, in order and without prompting:
#   sudo rm -rf fsroot*  ->  git clean -xfdf  ->  git reset --hard
make BLDENV=resolute UNATTENDED=y reset

# The two platforms must run serially: configure writes the shared .platform,
# so configuring broadcom while a vs build is still running would overwrite it.
sg docker -c 'make PLATFORM=vs configure'
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz target/sonic-vs.bin' > target/build-vs.log 2>&1

sg docker -c 'make PLATFORM=broadcom configure'
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin'          > target/build-broadcom.log 2>&1
```

The two vs installer targets are independent: `sonic-vs.img.gz` (`platform/vs/kvm-image.mk`, for KVM) and `sonic-vs.bin` (`platform/vs/one-image.mk`, for ONIE). The 08-23 run produced both (`.bin` at 16:28, `.img.gz` at 16:31) and chapter 1 cites the `.bin`, so the make line above asks for both. Drop one if you only need the other.

Check two host preconditions first, because a rebuild will fail without them: `lsmod | grep ip_tables` must return something, and `/etc/apparmor.d/local/gs` must exist (4.2 explains where that one comes from).

---

## Appendix: related documents and the limits of the evidence

In this directory: `2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-en.md` is the full account of auditing an in-service switch component by component and finding four defects, and 3.7 above is its final-state form. `2026-07-26-dut02-s5232f-validation-report-en.md` is the Dell S5232F hardware validation report. `resolute-modification-catalog-en.md` is a thematic snapshot from 2026-07-06 whose baseline (`77cfa809d`) has since been replaced by a rebase, so read it as history rather than as current state. `resolute-migration-code-review-en.md` and `resolute-vs-migration-report-en.md` are the early defect-oriented review and the per-package migration narrative. `specs/` and `plans/` hold the designs and execution plans for each phase.

The facts here come from five places, in decreasing order of reliability. Nearly all of chapter 3 comes from the repository itself: `git diff ba3fb8d5f5..202605_resolute_sheldon`, the file contents, and the line numbers. The 190 commits supply the rest of the history, particularly the revert pairs and the reorganization into `_mech` and `_real`. The build artifacts contribute their sizes and timestamps. Most of chapter 4's root-cause conclusions come from the Claude Code transcripts: 19 top-level JSONL files of roughly 38 MB covering 2026-07-24 onward, or 71 files and about 63 MB if the subagent subdirectories are counted. Finally, `~/.claude/history.jsonl` holds 203 prompts going back to 2026-07-02, human-side text only, and that is the source for the copy-then-rename review requirement in chapter 5 and the diff-hygiene standards in 4.6.

Two gaps to declare. First, `cleanupPeriodDays` defaults to 30 days, so transcripts from before 2026-07-24 have already been swept, and that window happens to be the bulk of the migration; it is reconstructable only from the commit history, `history.jsonl` and `docs/plans|specs`, which is why the earlier an incident is in chapter 4, the thinner its detail. The value was raised to 3650 on 2026-08-24, so under the current setting nothing further is removed by the 30-day policy. Second, any claim here that reaches inside a submodule or into a vendor platform repository — the state of flashrom's callers, for instance — comes from an earlier audit rather than this round of checking, and is marked as such where it appears.
