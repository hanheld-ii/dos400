# Porting analysis — `$HOME/AI/Projects/dos4-core` → this tree

Date: 2026-11-27
Status: analysis only, no source files modified.

## Context: 

dos4-core is a previous project to build upon the dos 4 source dump. For many reasons involving mangled source
and dissatisfaction with what I felt was an out of control build infrastructure, I decided to download neozeede's tree and use that as a base. 

Considerable work had been done in dos4-core, so this document is an attempt to see what can be re-used.

## 1. Method

Both trees descend from the MIT MS-DOS 4.00 release but share **no commit
ancestry**:

| tree | root commit | commits |
|---|---|---|
| `/home/random/hansrc/dos400` (this tree) | `43df989 MS-DOS 4.00 from Microsoft` → neozeed → hharte | 31 |
| `/home/random/AI/Projects/dos4-core` | `2a95a47 DOS 4.00 base with DOS 5 / 6.22 feature-recovery analysis` | 129 |

So this is **cross-base semantic porting, never `git cherry-pick`**.

Three comparisons were used:

1. `git diff --stat 2a95a47 HEAD -- src/` — 151 files, +31,745 / −8,144.
2. `git diff` vs `git diff -w` line counts per file — to separate whitespace
   churn from semantic change.
3. A pristine extraction of dos4-core's base at `/tmp/tmp.oHMrfYlMuO/w`
   (from commit `2a95a47`), diffed against this tree with
   `diff -w --strip-trailing-cr`. This is the important one: it shows what
   *this* tree already changed relative to a common ancestor, and what
   dos4-core changed on top of that same ancestor.

## 2. Formatting: the direction is the wrong way round

The working assumption was that dos4-core's pristine base still carries the
text-formatting defects and that this tree is the cleaned one. The data says
otherwise for every defect class that matters:

* `src/select/*` — this tree is *ahead* by 206/142/70/60/44/36/27/20/16/12/12
  lines (`panels`, `select2`, `select5`, `select4`, `select3`, `select2a`,
  `fastseek`, `select5a`, `select1`, `select9`, `select0`) plus 8 in
  `input.asm`, 4 in `routines.asm`/`colors.asm`, 2 in
  `select6`/`select7`/`scroll`. These are the mojibake repairs
  (`EF BF BD EF BF BD` → `#`, guessed glyphs, `WR_PIIND 'ÿ'` → `'?'`).
  dos4-core's base has none of them.
* `src/dev/display/int10com.inc` — 10 lines, this tree cleaned; base not.
* `src/bios/msinit.asm` — **verified byte-identical modulo whitespace/CRLF**
  to dos4-core's base. Nothing to port.
* `src/mapper/getmsg.asm:473` and `src/select/select7.asm:18` — the only
  genuine lingering cp437 divergence, and again this tree holds the correct
  bytes. dos4-core's base still has the damaged separator.

Conclusion: **no formatting repair needs to flow from dos4-core into this
tree.** The formatting work already done here is a superset. The formatting
problem the user identified is real, but it is an obstacle in the opposite
direction (this tree → dos4-core), not a portable payload.

## 3. Cleanly portable (small, isolated, verified absent here)

All three exist in dos4-core's **base** commit `2a95a47`, i.e. they are not
even part of its feature work — they are the two-line squashed fixes shipped
in the base import.

### 3.1 `src/inc/version.inc` — `ifndef` guards

dos4-core base lines 34–39:

```
ifndef IBMVER
IBMVER     EQU     TRUE      ; shipped default: IBM/clone variant (bootable)
endif
ifndef IBMCOPYRIGHT
IBMCOPYRIGHT EQU   FALSE
endif
```

This tree lines 34–35:

```
IBMVER     EQU     TRUE
IBMCOPYRIGHT EQU   FALSE
```

Effect: lets the build override the variant with `nmake IBMVER=FALSE` instead
of editing the file. No codegen change at default settings. **Clean port.**

### 3.2 `src/dos/exec.asm:250–251` — `JB` → `JS`

dos4-core base:

```
	JS	BadEnv			; gone beyond the end of the environment (CX wrapped 0->FFFFh)
					; [DOS 5 fix: DEC does not affect CF, so JB was never taken]
```

This tree:

```
	JB	BadEnv			; gone beyond the end of the environment
```

`DEC` does not modify `CF`, so `JB` after `DEC CX` tests a stale flag. With
`CX` = `0000h` the `DEC` wraps to `FFFFh` and a corrupt environment of
exactly 64 KiB is traversed. **Clean port**, one line plus comment.

### 3.3 `src/dos/ctrlc.asm` ~498 — EMS map restore

dos4-core base has, immediately after the `LABEL`/`PUSH` prologue:

```
IF	BUFFERFLAG
	invoke	RESTORE_USER_MAP		;AN000;LB. restore user's EMS map
ENDIF
```

This tree omits those three lines. Self-contained (`BUFFERFLAG` is the
ordinary IFSSYM switch, already defined in both trees), no dependency on the
DOS=HIGH work. **Clean port.**

> Note: the *rest* of dos4-core's `ctrlc.asm` is the DOS=HIGH refactor and is
> **not** portable on its own — see §5.

## 4. Portable with conflict resolution

### 4.1 `src/mapper/getmsg.asm:473` — separator bytes
Divergence is real but this tree is correct; treat as no-op.

### 4.2 `src/cmd/format/format.asm`
Direction reverses: this tree has the 32-bit `Relative_Sector_High` /
`OR BX,BX` / `JNZ` guards at ~622 and ~650 that dos4-core's base lacks.
dos4-core's HEAD instead did a different 32-bit refactor
(`tracksLeft dd`, `Divide_32_Bits`, `BPB_BigTotalSectors`). Neither is a
subset of the other. Porting either way means hand-merging. **Not clean.**

### 4.3 `src/dos/dev.asm:644`
This tree renamed `[CALLSSEC+2]` → `[HIGH_SECTOR]`. Same address, cosmetic.
Reverse direction; no port needed, but if dos4-core's file is ever taken
wholesale this line must be preserved.

## 5. Not portable (entangled with the DOS=HIGH / UMB body of work)

These are interdependent and cannot be taken file-by-file:

* `src/dos/ctrlc.asm` — `relDosHigh` guards, `Extrn DOSDS:WORD`,
  `MOV ES,CS:[DOSDS]` replacing `PUSH CS / POP ES`, `ctrlc_scratch DW ?`.
* `src/dos/ms_table.asm` — `FAKE_COUNT` `255`→`69`, UMB state block
  (`UMB_LINK_FLAG`/`UMB_COUNT`/`UMB_SENT`/`UMB_START`/`UMB_XMS_ENTRY`),
  `SNULDEV`/`INULDEV` retargeted to `118Ch`/`1192h`, A20 trampoline at
  `1193h`, `DB 5Dh DUP (0)` pad keeping `OLD_FIRSTCLUS` at `121Ch`.
* `src/inc/sysvar.inc` — `SYSI_BUFFERS DW ?,0` split into
  `SYSI_BUFFERS DW ?` / `SYSI_HBUFFERS DB 0` / `SYSI_DOSFLAGS DB 0`.
* `src/dos/msconst.asm` — **verified: this tree is identical to dos4-core's
  base**, still `I_am BUFFERS_PARM2,WORD,<0>` at line 90 with no `DOSFLAGS`.
  dos4-core HEAD has `BUFFERS_PARM2,BYTE,<0>` + `DOSFLAGS,BYTE,<0>`. The
  struct change only works together with the `sysvar.inc` split above.
* `src/dos/msinit.asm` — **verified identical to base**; the special-entry
  table removal is a dos4-core HEAD change only, and it sits inside the
  DOS=HIGH bootstrap path.
* `src/bios/sysinit1.asm` (339 ws / 5,437), `sysinit2.asm` (6 / 3,107),
  `sysconf.asm` (124 / 6,554) — banner, F5, `DOS=` keyword. Mostly
  whitespace, but the semantic part is inseparable from the relocation.
* `src/dos/alloc.asm` (462), `disp.asm` (190), `ms_code.asm` (77),
  `exec.asm` bulk, `share.asm`.

Also out of scope:

* New programs: `src/cmd/{zip,unzip,unzipsfx,chksum,setver,doskey,edit,devload,deltree,pager,mirror}`,
  `src/memm/memm/{xms.asm,gemmis.asm,gemmis.inc}`, `tools/`.
* Different build system: dos4-core uses `tools/build.sh` / `ci.sh` /
  `quicktest.sh` / `verify.py`; this tree uses `Makefile.AI` → `dosbuild.sh`
  → dosbox-x with `backup/mkdos.conf`.
* Missing here: `src/cmd/fdisk/fdiskm.c`.
* This tree is ahead on: `src/cmd/debug/debug.asm` (CALL 5 fix, +2),
  `src/bios/msload.asm` (`Mystacks` 64→128), `src/cmd/command/tranmsg.asm`
  (`Right_Align+Unsgn_Bin_Word`), `src/cmd/command/tcmd2a.asm` (+1),
  `src/setenv.bat` PATH, `src/cpy.bat`.

## 6. Recommended port set

Exactly three edits, all in `src/dos/`+`src/inc/`, all independently
testable, none touching the UMB/DOS=HIGH machinery:

1. `src/inc/version.inc` — wrap `IBMVER` / `IBMCOPYRIGHT` in `ifndef`/`endif`.
2. `src/dos/exec.asm:251` — `JB BadEnv` → `JS BadEnv` + comment.
3. `src/dos/ctrlc.asm` — insert the `IF BUFFERFLAG / invoke RESTORE_USER_MAP / ENDIF` block.

Everything else in dos4-core is either entangled with the DOS=HIGH/UMB
refactor, is a new program, or points the other way.
