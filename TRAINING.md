# Yocto Training Guide — Hands-On Labs

A practical, lab-driven introduction to the **Yocto Project**, written for this homelab's
build VM (`yocto-build`, Ubuntu 24.04, poky **scarthgap 5.0 LTS**, target `qemux86-64`).
Every lab here was run on that VM, so the commands and recipes are verified, not theoretical.

> **Where you work:** `ssh <user>@<build-vm>` → everything lives under `~/yocto/`
> (`poky/` = the build system, `build/` = your build dir, `meta-homelab/` = your own layer).
> Start every session with:
> ```bash
> cd ~/yocto && source poky/oe-init-build-env build
> ```
> That puts you in `~/yocto/build` with `bitbake` on your PATH.

---

## 1. The mental model (read this once)

Yocto doesn't ship a Linux distro — it's a **build system that builds your own distro**.

- **BitBake** — the task engine. Reads metadata and runs tasks (fetch → unpack → patch →
  configure → compile → install → package) to turn source into packages and images.
- **Recipe** (`.bb`) — instructions to build one piece of software (where to get the source,
  how to build it, what to install).
- **Layer** (`meta-*`) — a directory of related recipes/config. You add capabilities by
  adding layers (a BSP layer for new hardware, `meta-homelab` for your own stuff).
- **Image** — a recipe that defines a full root filesystem (a list of packages + image type).
- **Machine** — the target hardware (`qemux86-64`, `raspberrypi4`, …). Set by `MACHINE`.
- **Distro** — your policy/config layer (`poky` is the reference distro).
- **sstate-cache** — cached build output keyed by a hash of all inputs. This is why the
  *second* build is fast: unchanged tasks are restored instead of rebuilt.

Config lives in `build/conf/`: **`local.conf`** (machine, parallelism, your tweaks) and
**`bblayers.conf`** (which layers are active).

---

## 2. Glossary (terms you'll hit immediately)

| Term | Meaning |
|------|---------|
| `DL_DIR` | Where fetched source tarballs are cached (`~/yocto/downloads`) |
| `SSTATE_DIR` | Shared-state cache (`~/yocto/sstate-cache`) |
| `WORKDIR` | Per-recipe scratch dir under `build/tmp/work/...` |
| `S` | The source dir within `WORKDIR` (where `do_compile` runs) |
| `D` | The fake install dir (`do_install` stages files here, e.g. `${D}${bindir}`) |
| `${PN}` / `${PV}` | Package name / version |
| `:append` / `:prepend` / `:remove` | Override operators (Scarthgap uses `:`, not the old `_`) |
| `.bbappend` | A file that extends/modifies a recipe from another layer |
| `task` | A build step, e.g. `do_compile`. Run one with `bitbake -c <task> <recipe>` |

---

## Lab 1 — Build and boot a minimal image

**Goal:** confirm the whole pipeline works; see a Yocto-built Linux boot.

```bash
cd ~/yocto && source poky/oe-init-build-env build
bitbake core-image-minimal          # first time ~1–2h; cached after
runqemu qemux86-64 nographic        # boots the image in QEMU
```
- Log in as **root** (no password). Poke around: `uname -a`, `ls /`, `cat /etc/os-release`.
- **Exit QEMU:** `Ctrl-A`, then `X`.

**You learned:** the build → image → boot loop, and that `runqemu` wires up the kernel +
rootfs this build produced. Sources came from the NAS mirror (see this repo's README).

---

## Lab 2 — Explore the build (no changes)

**Goal:** learn the introspection tools — these are how you answer "where does X come from?"

```bash
bitbake-layers show-layers                 # active layers
bitbake-layers show-recipes | head -40     # recipes you can build
bitbake -s | grep -i busybox               # is busybox available? what version?
bitbake-getvar -r core-image-minimal IMAGE_INSTALL   # what goes in the image
bitbake -c listtasks busybox | head        # tasks for a recipe
bitbake -e busybox | grep ^WORKDIR=        # the fully-expanded value of a variable
```

**You learned:** `bitbake-layers`, `bitbake -s`, `bitbake-getvar`, and `bitbake -e`
(the "show me the final value of everything" command — your #1 debugging tool).

---

## Lab 3 — Add a package to your image

**Goal:** change what's *in* the image without writing a recipe.

Edit `build/conf/local.conf`, add a line:
```
IMAGE_INSTALL:append = " nano dropbear"
```
Then:
```bash
bitbake core-image-minimal
runqemu qemux86-64 nographic
#   in the guest:  which nano   (it's now there)
```

**You learned:** `IMAGE_INSTALL:append` (note the leading space and the `:append` operator)
adds packages to an image. `dropbear` even gives the QEMU guest an SSH server.

---

## Lab 4 — Create your own layer

**Goal:** make a home for your own recipes. (Verified on this VM.)

```bash
cd ~/yocto
bitbake-layers create-layer meta-homelab          # scaffolds the layer
bitbake-layers add-layer meta-homelab             # activates it (edits bblayers.conf)
bitbake-layers show-layers | grep homelab         # confirm it's active
```

**You learned:** a layer is just a directory with a `conf/layer.conf`; `create-layer` +
`add-layer` do the boilerplate. Keep *your* changes here, never edit `poky/`.

---

## Lab 5 — Write a custom recipe

**Goal:** package your own software. We'll install a script. (Verified — note the
Scarthgap `${WORKDIR}` detail.)

```bash
RD=~/yocto/meta-homelab/recipes-homelab/hello-homelab
mkdir -p $RD/files
cat > $RD/files/hello-homelab.sh <<'EOS'
#!/bin/sh
echo "Hello from the Rogers homelab Yocto build!"
EOS
cat > $RD/hello-homelab_1.0.bb <<'EOB'
SUMMARY = "Homelab hello-world script"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
SRC_URI = "file://hello-homelab.sh"
S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/hello-homelab.sh ${D}${bindir}/hello-homelab
}
EOB
bitbake hello-homelab
```
Build it; success ends with `Tasks Summary: ... all succeeded`. The packaged binary lands at
`build/tmp/work/core2-64-poky-linux/hello-homelab/1.0/image/usr/bin/hello-homelab`.

> **Scarthgap gotcha:** local `SRC_URI` files unpack to **`${WORKDIR}`** here (the older
> `${UNPACKDIR}` is empty). If `do_install` says *"cannot stat '/yourfile'"*, that's why —
> use `${WORKDIR}/yourfile`.

**You learned:** the anatomy of a recipe — `LICENSE` + `LIC_FILES_CHKSUM` (mandatory),
`SRC_URI` (where source comes from), and `do_install` staging into `${D}`.

---

## Lab 6 — Put your recipe in an image and run it

**Goal:** ship your package and execute it on the target.

```bash
echo 'IMAGE_INSTALL:append = " hello-homelab"' >> ~/yocto/build/conf/local.conf
bitbake core-image-minimal
runqemu qemux86-64 nographic
#   in the guest:  hello-homelab     -> prints your message
```

**You learned:** the full custom-software path — recipe → image → boot → run. This is the
core Yocto workflow in miniature.

---

## Lab 7 — Modify an existing recipe with a `.bbappend`

**Goal:** change a recipe you don't own, the right way (no editing `poky/`).

Append to BusyBox's recipe by creating a matching `.bbappend` in your layer:
```bash
mkdir -p ~/yocto/meta-homelab/recipes-core/busybox
# match the busybox version: bitbake -s | grep busybox
cat > ~/yocto/meta-homelab/recipes-core/busybox/busybox_%.bbappend <<'EOB'
# %.bbappend matches ANY version of busybox
do_install:append() {
    install -d ${D}${sysconfdir}
    echo "tuned by meta-homelab" > ${D}${sysconfdir}/homelab-marker
}
EOB
bitbake busybox -c install -f
```

**You learned:** `.bbappend` files (named to match the recipe, `%` = any version) layer
changes on top of upstream recipes — the cornerstone of customizing without forking.

---

## Lab 8 — The `devtool` workflow

**Goal:** the modern, ergonomic way to add/modify software.

```bash
# add an upstream project as a recipe, automatically:
devtool add https://github.com/jgrahamc/jgrep   # example: fetches, guesses build, makes a recipe
devtool build jgrep
devtool finish jgrep meta-homelab               # graduates the recipe into your layer
# or modify an existing recipe's source interactively:
devtool modify busybox     # checks out source you can edit + rebuild with `devtool build`
devtool reset busybox      # when done
```

**You learned:** `devtool` automates recipe creation and gives you a git-backed workspace
for hacking on a package, then `finish` writes a proper recipe into your layer.

---

## Lab 9 — Inspect and debug

**Goal:** the tools you'll reach for when a build breaks or behaves oddly.

```bash
# every task writes a log:
ls build/tmp/work/core2-64-poky-linux/hello-homelab/1.0/temp/log.do_*
# drop into the recipe's exact build environment (cross-compiler, vars all set):
bitbake -c devshell hello-homelab
# what package owns a file / what files a package ships:
oe-pkgdata-util find-path /usr/bin/hello-homelab
oe-pkgdata-util list-pkg-files hello-homelab
# track what changed image-to-image:
echo 'INHERIT += "buildhistory"'            >> build/conf/local.conf
echo 'BUILDHISTORY_COMMIT = "1"'            >> build/conf/local.conf
```

**You learned:** `temp/log.do_*` (per-task logs), `bitbake -c devshell` (interactive build
env), `oe-pkgdata-util` (package introspection), and `buildhistory` (image diffing).

---

## Lab 10 — Stretch goals

- **Bigger images:** `bitbake core-image-full-cmdline` (more tools), or
  `core-image-sato` (a graphical image — boot with `runqemu qemux86-64`).
- **A custom image recipe:** create `meta-homelab/recipes-core/images/homelab-image.bb`:
  ```
  require recipes-core/images/core-image-minimal.bb
  IMAGE_INSTALL:append = " hello-homelab nano dropbear openssh"
  ```
  then `bitbake homelab-image`.
- **Real hardware:** add the `meta-raspberrypi` BSP layer, set `MACHINE = "raspberrypi4-64"`,
  build `core-image-base`, and flash the `.wic` to an SD card. The recipe/layer skills
  transfer 1:1 from QEMU.
- **A custom distro:** define your own `DISTRO` in a `meta-homelab/conf/distro/*.conf`.

---

## Cheat sheet

```bash
source poky/oe-init-build-env build      # enter the env (from ~/yocto)
bitbake <image|recipe>                   # build something
bitbake -c <task> <recipe>               # run one task (fetch, compile, install, devshell…)
bitbake -c cleansstate <recipe>          # force a clean rebuild of a recipe
bitbake -s                               # list recipes + versions
bitbake -e <recipe> | grep ^VAR=         # final value of a variable
bitbake-getvar -r <recipe> VAR           # same, friendlier
bitbake-layers show-layers|add-layer|create-layer
runqemu qemux86-64 nographic             # boot the built image (Ctrl-A X to quit)
devtool add|modify|build|finish          # assisted recipe workflow
```

**Common pitfalls**
- *"User namespaces are not usable by BitBake"* → already fixed on this VM
  (`kernel.apparmor_restrict_unprivileged_userns=0`).
- *`do_install: cannot stat '/file'`* → use `${WORKDIR}/file` (see Lab 5).
- *Missing license error* → set `LICENSE` + a correct `LIC_FILES_CHKSUM`.
- Disk filling up → `DL_DIR`/`SSTATE_DIR` persist by design; add `INHERIT += "rm_work"` to
  drop per-recipe work dirs.

## Where to go deeper
- Yocto Mega Manual: https://docs.yoctoproject.org/scarthgap/
- Recipe & Style Guide: https://docs.yoctoproject.org/scarthgap/contributor-guide/recipe-style-guide.html
- BitBake User Manual: https://docs.yoctoproject.org/bitbake/
