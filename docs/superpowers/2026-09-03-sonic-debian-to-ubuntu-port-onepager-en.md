# How we ported SONiC from Debian to Ubuntu

SONiC is the open-source network OS behind a growing number of data-centre switches, and its community build has always been Debian-based. We think it belongs on Ubuntu, like the servers next to it: one security-maintained base, a long support horizon, one kernel and toolchain from host to switch. So we ported the community build to Ubuntu 26.04 LTS, on virtual and Broadcom switches.

## Overview of changes

We expected to swap the base image; we found five kinds of difference:

- **Distribution structure.** GRUB and the kernel are packaged differently, `resolvconf` no longer exists, and rsyslog and hostname carry enforced AppArmor profiles.
- **Newer toolchain.** GCC 15 defaults to C23; Python 3.14 enforces PEP 668. Newer was not always better — we pinned Boost *back* to the version Debian uses.
- **Linux 7.0 kernel.** A dozen classes of API drift in Broadcom's out-of-tree drivers.
- **Hard-coded release names.** "trixie" baked into container templates and build rules.
- **Stricter packaging tools.** dpkg rejects sloppy metadata; debug packages arrive as unexpected `.ddeb` files.

Two rules shaped every decision: change nothing Ubuntu does not need, and keep mechanical renames separate from real changes so reviewers can tell them apart. Both images build from a clean checkout; the Broadcom image has been validated on a Dell switch with BGP up.

## Using our AI angels (agents)

One engineer and Claude Code did this in two months.

**Our approach.** We gave the agent an end state, not a task list: "the VM boots Ubuntu 26.04 on a 7.0 kernel with every container running." It looped on its own — build, fail, diagnose, fix, clean, retry. Commits were allowed; pushes were not. That loop found a bug no build log could show: an installer path that only broke on boot.

**Human review.** Every agent conclusion was a claim to verify, and the sharpest corrections were common sense — Ubuntu's own bash cannot fail to build on Ubuntu. Independent AI reviewers were no guarantee: three converged on the same wrong answer. An outside human reviewer caught "already fixed upstream" comments written without checking.

**Testing.** Acceptance meant a from-scratch rebuild with build caches wiped — warm caches had hidden real bugs. A clean exit code guaranteed nothing: FRR built fine but shipped without its SONiC forwarding module, found only when BGP failed on hardware. Re-enabling the package tests then surfaced the most Ubuntu-specific bug: a default linker option that stopped the test mocks from intercepting library calls. One build flag fixed it, and the suite passed with no Redis.
