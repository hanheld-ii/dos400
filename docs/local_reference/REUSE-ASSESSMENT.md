# Re-use assessment — `src/cmd/format` changes and the new utilities in dos4-core

Date: 2026-11-27
Companion to `docs/PORTING-ANALYSIS.md`. Analysis only; no source modified.

Short answer: **take FORMAT (both parts), take EDIT/ZIP/UNZIP/UNZIPSFX essentially
as-is, take DOSKEY plus its three-line COMMAND.COM hook.** Nothing on this list
is worth re-implementing from scratch. Details and the caveats follow.

---

## 1. FORMAT — take it, it is the best-engineered change in that tree

`git diff 2a95a47 HEAD -- src/cmd/format/` is 209 changed lines of which 205
survive `-w`: essentially **zero formatting noise**, all substance.
Four files, +153 / −48.

### 1.1 The 32-bit track arithmetic (`format.asm`, ~150 lines)

This is a genuine bug fix, not a feature. In this tree, at
[`src/cmd/format/format.asm:326`](src/cmd/format/format.asm:326):

```
tracksLeft      dw  ?
tracksPerDisk   dw  ?
```

Both are **16-bit**. [`Phase2Initialisation`](src/cmd/format/format.asm:2126)
divides `BPB_BigTotalSectors` (32-bit) by `BPB_SectorsPerTrack` and stores the
quotient with `mov tracksPerDisk, ax` — the high half is discarded. For any
disk whose track count exceeds 65,535 the count wraps and FORMAT stops early
or reports nonsense progress. dos4-core's fix:

* `tracksLeft dd ?` / `tracksPerDisk dd ?`
* all four uses converted to 32-bit (`Phase2Initialisation`, `StdBPB`,
  `CurrentLogicalSector`, `NextTrack`, `Calc_Track_Count`, `Adj_Track_Count`,
  `DisplayCurrentTrack`)
* a new `Divide_32x32` routine — shift-and-subtract, explicitly 8086-safe, no
  `DIV` overflow risk, documented input/output contract

The `NextTrack`/`Calc_Track_Count`/`Adj_Track_Count` conversions are the fiddly
part (`or ax, TracksLeft+2` zero-tests, `sbb` borrow propagation) and they are
done correctly. Re-deriving this would cost a day and gain nothing.

**Conflict note:** this tree independently added
`mov bx,word ptr Relative_Sector_High / OR BX,BX / JNZ CLRTEST` guards at
[`format.asm:622`](src/cmd/format/format.asm:622) and `:650`. Those guard
against a *different* bug (sector number overflow in the packet setup). They
are compatible in intent but sit in a region dos4-core also rewrote, so that
one hunk needs a hand merge. Everything else in the diff applies directly.

### 1.2 `/U` unconditional format (`forparse.inc`, `forinit.asm`, `msfor.asm`)

Adds a `/U` switch to the parser table and, in `forinit.asm`, accepts it as a
no-op with a comment pointing at the measurement that justifies it: this
FORMAT already rewrites only boot/BPB/FAT/root and never touches data
clusters, so "unconditional" has nothing extra to destroy. `msfor.asm` drops
`SWITCH_AUTOTEST` from the "interesting switches" masks so the new switch
doesn't trip the combination checks.

This is a **compatibility stub**, ~30 lines. Worth taking so scripts that pass
`/U` don't fail, but it is not doing real work — do not claim otherwise in the
docs.

**Verdict: take both halves. The 32-bit arithmetic is the valuable part.**

---

## 2. EDIT, ZIP, UNZIP, UNZIPSFX — take as-is, they are clean-room C

Sizes: `edit.c` 91 KB, `zip.c` 36 KB, `unzip.c` 39 KB, `unzipsfx.c` 28 KB.

Decisive property: all four are written from public specifications (pkzip 
2.04g's APPNOTE.txt in the case of zip,unzip and unzipsfx) or implemented
from scratch (in the case of edit)

Dependencies are bounded:

* Includes only `<stdio.h> <stdlib.h> <string.h> <stdarg.h> <ctype.h>
  <dos.h> <conio.h> <bios.h> <direct.h>` — all supplied by the MSC 5.10
  toolchain already vendored at [`src/tools`](src/tools) in this tree
  (`cl.exe`, `link.exe`, `lib.exe` all present).
* `edit.c` uses `int86`/`intdos` and notes "this dos.h has no MK_FP" — already
  adapted to the actual header in this tree. Same `src/h` headers, no
  tree-specific includes (dos4-core added nothing to `src/h`).
* Build convention is identical to existing utilities here: `cl -c -AS -Os -Zp
  -I. -I$(hinc)`, `link ... ,NUL.MAP,,;`. Compare
  [`src/cmd/attrib`](src/cmd/attrib) and [`src/cmd/fdisk`](src/cmd/fdisk),
  which build the same way. `edit` uses `-AC` (compact) instead of `-AS`
  because the line list needs to cross 64 KB via `INT 21h/48h` arenas.
* No XMS/EMS calls in zip/unzip; XMS is confined to `edit`'s optional
  `xmstrial.md` notes, not `edit.c` itself.

Practical value: the ZIP family is a real feature no other DOS 4 tree has, and
`unzipsfx` correctly handles the `base = actual_cd_position - eocd.cd_offset`
correction for stub-prefixed archives — non-obvious, easy to get wrong,
already tested. `edit.c` is a self-contained ~2500-line editor with no
undo/search/mouse, i.e. honestly scoped.

**Verdict: take all four verbatim with their makefiles. This is the highest
value-per-risk item in the whole tree.**

---

## 3. DOSKEY — take it, but it needs a COMMAND.COM hook in this tree

[`src/cmd/doskey/doskey.asm`](src/cmd/doskey/doskey.asm) is 60 KB of
hand-written MASM: INT 21h AH=0Ah interception, INT 2Fh AX=4800h/48F0h
multiplex, transient/resident split with INT 27h, separate history/macro
block freesable by `/UNLOAD`. It should be noted that this doskey is an
independant implementation and was created without reference to any 
other doskey binaries or source code. (not IBM/MS DOS, not FreeDOS, etc)

**The dependency that matters:** DOSKEY distinguishes a shell command line
from COMMAND.COM's DATE/TIME prompts — both use AH=0Ah — by a marker the
shell emits first. dos4-core added it in `2dc3b5b` to
[`src/cmd/command/tcode.asm`](src/cmd/command/tcode.asm:357), three lines
inside `REGCOM`:

```
	MOV	AX,48F0h			; DOSKEY: mark the shell line
	INT	2Fh
	MOV	DX,OFFSET TRANGROUP:UCOMBUF	; reload: a chained handler may clobber DX
```

I checked this tree: grep for `48F0` across `src/cmd/command/` returns
**nothing**, and across all `*.asm`/`*.inc` only an unrelated `4800h` in
[`emminit.asm`](src/memm/memm/emminit.asm:399). So a straight copy of
`doskey.asm` would install and appear to work while silently treating every
DATE/TIME prompt as a history entry.

The hook itself is safe to add: `INT 2Fh` with an unknown `AX` is required to
be ignored by every well-behaved TSS, and the `MOV DX,...` reload defends
against a chained handler clobbering `DX`. Cost: 3 lines, no behaviour change
when DOSKEY is absent.

**Verdict: take `doskey.asm` + makefile *and* the `tcode.asm` hook as one
unit.** Also take `docs/findings-11-doskey.md` (532 lines) and the Python
oracle/compare scripts — the commit claims 26/26 functional checks on DOS 4,
and those tests are the only evidence the thing works.

Caveat to record honestly: DOSKEY hooks AH=0Ah, which is the DOS 4 line
editor. It will not behave correctly under a shell that bypasses DOS for input
reads. `/SHELLONLY` (the default) is the conservative mode; `/ALL` is the
opt-in.

---

## 4. What not to bother with

* `mirror`/`unformat` — interesting but entangled with the FORMAT `/U`
  semantics story; take only after FORMAT lands and you can re-measure.
* `setver`, `devload`, `deltree`, `pager`, `chksum` — small, low risk, but
  also low value; take opportunistically when you are already touching
  `src/cmd/makefile`.
* `memm/memm/{xms.asm,gemmis.asm}` — this is the UMB/DOS=HIGH body of work,
  not a drop-in utility. Skip unless you are doing the relocation port.
* `tools/` — different build system entirely (`build.sh`/`ci.sh`/`verify.py`).
  Read `tools/doskey-test.sh` for ideas; do not import the harness.

---

## 5. Suggested order

1. **FORMAT 32-bit arithmetic** — real bug fix, self-contained, independently
   testable on a large disk image. Hand-merge the two `Relative_Sector_High`
   hunks.
2. **COMMAND.COM `tcode.asm` hook + DOSKEY** — must go in together.
3. **ZIP / UNZIP / UNZIPSFX** — pure additions, no conflict surface at all.
4. **EDIT** — pure addition, but largest single file; needs `-AC` and an
   `INT 21h/48h` memory test.
5. **FORMAT `/U`** — cosmetic compatibility, do last.

Items 2–4 have no overlap with anything this tree already changed, so they can
be applied without touching existing code paths. Only item 1 intersects work
already done here.
