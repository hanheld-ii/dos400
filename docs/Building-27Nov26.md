## Building

The build runs entirely inside [DOSBox-X](https://dosbox-x.com/), which provides the
real DOS environment needed by the 1980s Microsoft toolchain (MASM, CL, LINK, NMAKE)
shipped in [`src/tools/`](src/tools).

### Prerequisites

| Requirement | Notes |
|---|---|
| `dosbox-x` on `PATH` | Host package or local build |
| `backup/mkdos.conf` | DOSBox-X config whose `[autoexec]` drives the build. **Gitignored** |
| `backup/tools.txz` | Archive used to restore the vendored toolchain after a clean. **Gitignored** |

Because `backup/` is listed in [`.gitignore`](.gitignore:3), a fresh clone will not
contain the config or the toolchain archive. Both must be present locally before
building.

### The build loop

The normal workflow after editing anything under [`src/`](src) is:

```sh
make -f Makefile.AI clean
make -f Makefile.AI build
```

`clean` removes previous output; `build` recompiles everything and gathers the
results. Running `build` on its own does **not** clean first, so it is incremental
with respect to whatever NMAKE finds on disk. When in doubt, run both.

### What happens during a build

[`Makefile.AI`](Makefile.AI:1) is a thin wrapper. `build` invokes
[`dosbuild.sh`](dosbuild.sh:3), which launches:

```sh
dosbox-x -conf backup/mkdos.conf
```

The `[autoexec]` section of [`backup/mkdos.conf`](backup/mkdos.conf:6) then runs:

1. `mount c .` — mounts the repository root as `C:`.
2. `mount d ./.d` — mounts a scratch area as `D:`.
3. `call c:\mkit.bat` — the compile stage.
4. `call c:\src\mkboot.bat` — the disk image stage.
5. `exit` — closes DOSBox-X.

**Stage 1 — compile.** [`mkit.bat`](mkit.bat:1) changes to `src`, runs
[`src/setenv.bat`](src/setenv.bat:1) to establish `LIB`, `INCLUDE` and `PATH` for the
vendored compiler, then runs `nmake` at the [`src/makefile`](src/makefile:1) root.
That makefile recurses through `messages`, `mapper`, `boot`, `bios`, `dos`, `cmd`,
`dev`, `select` and `memm`. Finally [`src/cpy.bat`](src/cpy.bat:1) copies every
finished binary into `C:\build`.

**Stage 2 — images.** [`src/mkboot.bat`](src/mkboot.bat:1) sets the reported DOS
version, mounts `build/`, and uses DOSBox-X's own disk tools to create and populate
the images described below.

### Output

| Path | Contents |
|---|---|
| `build/` | Every compiled binary, gathered by [`src/cpy.bat`](src/cpy.bat:1) |
| `out/dos4boot12.img` | 1.2 MB bootable floppy image |
| `out/dos4boot144.img` | 1.44 MB bootable floppy image |
| `out/dos4hd.vhd` | 40 MB fixed-size VHD with a `\DOS4` directory |

### Booting the images

The images boot under DOSBox-X directly. For the 1.44 MB floppy:

```sh
dosbox-x -c "imgmount a out/dos4boot144.img" -c "boot a:"
```

For the 40 MB hard disk:

```sh
dosbox-x -c "imgmount c out/dos4hd.vhd" -c "boot c:"
```

The floppy images are also suitable for [86Box](https://86box.net/). The VHD can be
attached as a hard disk in either emulator.

### Cleaning

[`clean.sh`](clean.sh:1) performs five jobs:

1. Deletes build output under `src/` by uppercase extension — `CL1`–`CLF`, `CTL`,
   `CPI`, `MAP`, `OBJ`, `EXE`, `COM` and `SYS`.
2. Removes `build/` entirely and recreates it empty, so a failed build cannot leave
   stale binaries behind.
3. Removes `IO.SYS` and `MSDOS.SYS` if they were written to the repository root.
4. Deletes generated disk images, `out/*.img` and `out/*.vhd`.
5. Restores the vendored toolchain from `backup/tools.txz`.

The extension matching is deliberately **case-sensitive**. Build products are
uppercase (`IO.SYS`, `MSBIO1.OBJ`) while the files inside [`src/tools/`](src/tools)
are lowercase (`cl.exe`, `binmode.obj`). Matching case-insensitively would delete the
compiler itself.

The toolchain restore runs last, so [`src/tools/`](src/tools) is always left in a
usable state even after a clean that removes compiler output.

### Notes and current limitations

- [`src/mkboot.bat`](src/mkboot.bat:1) expects an `out/` directory to exist; it does
  not create one. Create it once with `mkdir out` before the first build.
- `clean.sh` uses `rm {IO,MSDOS}.SYS` without `-f`, so it prints an error if those
  files are absent. The script has no `set -e`, so it still continues to the image
  cleanup and toolchain restore and exits 0. The message is cosmetic, but it appears
  on any tree that never had those files at the root.
- `out/` is **not** in [`.gitignore`](.gitignore:1), so generated images will show up
  as untracked files in `git status`.

---

