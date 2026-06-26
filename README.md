# yocto-homelab

Building a minimal embedded Linux image with the **[Yocto Project](https://www.yoctoproject.org/)**
(Scarthgap 5.0 LTS) and booting it under QEMU — a hands-on homelab learning project.

Target: `qemux86-64` (QEMU x86-64 emulation). Result: a `core-image-minimal` that boots
to a login prompt under `runqemu`.

```
Poky (Yocto Project Reference Distro) 5.0.18 qemux86-64 /dev/ttyS0
qemux86-64 login:
```

- **Kernel:** 6.6.142-yocto-standard
- **Distro:** Poky 5.0.18 (scarthgap)
- **Toolchain:** GCC 13.4.0, binutils 2.42

---

## Build host

A dedicated Linux build VM (Ubuntu 24.04 LTS) on a Proxmox hypervisor — Yocto builds are
CPU-bound and benefit from many cores:

- 24 vCPU / 64 GB RAM / 250 GB disk
- First `core-image-minimal` build: ~4,076 tasks (compiles the full native toolchain)
- Rebuilds are far faster thanks to the shared-state (`sstate`) cache

### Host dependencies (Ubuntu 24.04)
```bash
sudo apt-get install -y \
  gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio \
  python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping \
  python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales \
  libacl1 libsdl1.2-dev
sudo locale-gen en_US.UTF-8
```

---

## Quick start

```bash
# 1. Clone poky (the Yocto reference distro), scarthgap branch
git clone -b scarthgap https://git.yoctoproject.org/poky
# (GitHub mirror: https://github.com/yoctoproject/poky)

# 2. Initialise the build environment (drops you into ./build)
source poky/oe-init-build-env build

# 3. Apply the customisations in conf/local.conf.sample (see below), then build
bitbake core-image-minimal

# 4. Boot it in QEMU (headless / serial console)
runqemu qemux86-64 nographic
# login: root (no password).  Exit QEMU: Ctrl-A then X
```

`scripts/run-build.sh` wraps steps 2–3 for repeatable, loggable builds (handy under `tmux`).

---

## `conf/local.conf` customisations

See [`conf/local.conf.sample`](conf/local.conf.sample). Highlights:

- **Parallelism** tuned to the host core count (`BB_NUMBER_THREADS` / `PARALLEL_MAKE`).
- **Shared source mirror** scaffolding (`SOURCE_MIRROR_URL` + `own-mirrors` +
  `BB_GENERATEMIRRORTARBALLS`) so sources are fetched once and reused across builds/hosts —
  and optionally built fully offline.

---

## Gotchas & lessons learned

### Ubuntu 24.04 blocks BitBake (AppArmor / user namespaces)
BitBake needs unprivileged user namespaces, which Ubuntu 24.04 (Noble) restricts by default.
Symptom:
```
ERROR: User namespaces are not usable by BitBake, possibly due to AppArmor.
```
Fix (persistent):
```bash
echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee /etc/sysctl.d/60-yocto-userns.conf
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

### Disk usage
`build/tmp` reaches tens of GB. `downloads/` (`DL_DIR`) and `sstate-cache/` (`SSTATE_DIR`)
persist and are reusable — keep them on a roomy/shared volume. Add `INHERIT += "rm_work"`
to reclaim per-recipe work directories once you no longer need to inspect them.

### CPU, not RAM, is the bottleneck
`core-image-minimal` peaks at a few GB of RAM but saturates every core. Scale vCPUs (and
`BB_NUMBER_THREADS` / `PARALLEL_MAKE`) before adding memory.

---

## Roadmap

- [x] Build `core-image-minimal` for `qemux86-64` and boot it under `runqemu`
- [ ] `core-image-full-cmdline` and `core-image-sato`
- [ ] A custom layer (`bitbake-layers create-layer meta-homelab`) with an image + recipe
- [ ] A shared NFS source mirror for fast/offline builds
- [ ] `meta-raspberrypi` BSP to cross-build for real hardware

---

## License

Documentation and scripts here are MIT-licensed. The Yocto Project / OpenEmbedded layers
referenced (poky, etc.) carry their own upstream licenses.
