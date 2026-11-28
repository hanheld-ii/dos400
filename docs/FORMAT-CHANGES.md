# FORMAT changes applied to this tree

**Written:** 2026-11-28T00:08Z (2026-11-27 15:08 AKST)
**Tree:** `/home/random/hansrc/dos400` (DOS 4.00, root commit `43df989`)
**Source of the port:** `/home/random/AI/Projects/dos4-core`, commit `2c6501a`
— *"format: 32-bit sector and track arithmetic for large media"*
(Harper Held, 2026-11-07 12:54 -0900; 1 file changed, +127 / −40 was the
`format.asm` part of it, plus the `/U` switch work from `e486491`).

---

## 1. Summary

Two separate bodies of work are recorded here.

The first is the `2c6501a` port: the format track and sector arithmetic is now
32-bit, so sector totals and hidden-sector counts above 65535 no longer wrap.

The second, added later the same day, is **2.88 MB extended-density support**
(§6). It is a change of the opposite kind from §6's original heading — that
section used to say 2.88 MB was deliberately unsupported, and it now documents
the support instead.

| File | Change |
|---|---|
| [`src/cmd/format/format.asm`](../../src/cmd/format/format.asm) | 32-bit track/sector arithmetic; new `Divide_32x32` routine; `DiskTable` comment explaining why no 2.88 MB row is needed |
| [`src/cmd/format/forparse.inc`](../../src/cmd/format/forparse.inc) | `/U` switch registration (parsed, inert); six `/F:2880` spellings, string count 27 → 33 |
| [`src/cmd/format/forinit.asm`](../../src/cmd/format/forinit.asm) | `/U` consumed as a no-op (untouched by the 2.88 MB work) |
| [`src/cmd/format/msfor.asm`](../../src/cmd/format/msfor.asm) | switch-mask relaxation for `/U`; `Size_2880` handling in `Other_Drives`; `BPB2880` template copied by `Check_720`; FAT12/FAT16 dispatch in `Calc_Total` |
| [`src/cmd/format/forswtch.inc`](../../src/cmd/format/forswtch.inc) | `Size_2880 equ 0080h` |

Build result recorded before the 2.88 MB work: `build/FORMAT.COM`, 23,051
bytes, MD5 `f3a02e459d569a45e41ab574d924f42b`, built 2026-11-27 14:54 local by
a whole-tree rebuild. The tree has since been edited again for 2.88 MB and has
**not** been rebuilt — see §8.

---

## 2. `format.asm` — 32-bit sector and track arithmetic

### 2.1 Storage widened

```asm
tracksLeft      dd  ?      ; was: dw
tracksPerDisk   dd  ?      ; was: dw
```

Everything that reads or writes these two now handles both words. There is no
remaining 16-bit-only use in the file.

### 2.2 First track (round up)

Original used `div BPB_SectorsPerTrack` on a value assembled in `AX:DX`; the
quotient was truncated to 16 bits, so a hidden-sector count whose track
quotient exceeded 65535 wrapped.

```asm
	mov	di, deviceParameters.DP_BPB.BPB_HiddenSectors
	mov	si, deviceParameters.DP_BPB.BPB_HiddenSectors + 2
	add	di, deviceParameters.DP_BPB.BPB_SectorsPerTrack
	adc	si, 0
	dec	di
	sbb	si, 0
	mov	cx, deviceParameters.DP_BPB.BPB_SectorsPerTrack
	call	Divide_32_Bits				;SI:DI = (Hidden + SPT - 1) / SPT
	mov	ax, di					;combined cyl/head count
	xor	dx,dx
	div	deviceParameters.DP_BPB.BPB_Heads
	mov	firstCylinder, ax
	mov	firstHead, dx
```

### 2.3 Total track count (round down)

`BPB_TotalSectors` is a 16-bit field; `BPB_BigTotalSectors` is 32-bit. The
original zero-extended `TotalSectors` into `DX:AX` and divided, so any volume
over 65535 sectors came out short. It now falls back to the big field when the
small one is zero, and divides with `Divide_32_Bits`.

```asm
; BPB_TotalSectors is a 16 bit field; BPB_BigTotalSectors is 32 bit
	mov	di, deviceParameters.DP_BPB.BPB_TotalSectors
	xor	si,si
	or	si,di
	jnz	NotBigTotalSectors
	mov	di, word ptr deviceParameters.DP_BPB.BPB_BigTotalSectors
	mov	si, word ptr deviceParameters.DP_BPB.BPB_BigTotalSectors+2
NotBigTotalSectors:
	mov	cx, deviceParameters.DP_BPB.BPB_SectorsPerTrack
	call	Divide_32_Bits				;SI:DI = total sectors / SPT
	mov	word ptr tracksPerDisk, di
	mov	word ptr tracksPerDisk+2, si
```

`Phase2Initialisation` as applied is byte-identical to the dos4-core version.

### 2.4 `StdBPB` seed of `tracksLeft`

```asm
	mov	ax, word ptr tracksPerDisk
	mov	dx, word ptr tracksPerDisk+2
	mov	word ptr tracksLeft, ax
	mov	word ptr tracksLeft+2, dx
```

### 2.5 `DisplayCurrentTrack` — percent complete

The old code did `div TracksPerDisk`, which divides `DX:AX` by a 16-bit divisor;
once `tracksPerDisk` exceeded 65535 that raises divide error. It now uses the
new 32×32 routine:

```asm
	mov	si,bx				; dividend high
	mov	di,ax				; dividend low
	mov	cx,word ptr TracksPerDisk	; divisor low word
	mov	dx,word ptr TracksPerDisk+2	; divisor high word
	call	Divide_32x32			;AX = % complete
```

### 2.6 `CurrentLogicalSector`

```asm
; current track = tracksPerDisk - tracksLeft	(32 bit subtract)
	mov	ax, word ptr tracksPerDisk
	mov	bx, word ptr tracksPerDisk+2
	sub	ax, word ptr tracksLeft
	sbb	bx, word ptr tracksLeft+2
; multiply by sectors per track
	...
	mov	word ptr Relative_Sector_High,bx
	mov	word ptr Relative_Sector_Low,ax
```

### 2.7 New routine `Divide_32x32`

Inserted after `Divide_32_Bits endp`, roughly 60 lines, restoring
shift-and-subtract division, no 80286 instructions.

```asm
; Inputs  : SI:DI - dividend (32 bit)
;           DX:CX - divisor  (32 bit)
; Outputs : AX    - quotient, valid when the true quotient is < 65536
;                   (which is the case for the percent-complete calculation)
; Uses    : restoring shift-and-subtract, 8086/88 safe.
```

### 2.8 Remaining 32-bit users

- `NextTrack` — replaced `cmp TracksLeft,00` with
  `mov ax,word ptr TracksLeft / or ax,word ptr TracksLeft+2`.
- `Calc_Track_Count` — tests `TracksLeft+2` first; when the high word is
  non-zero the 16-bit `Track_Count` is by definition the smaller value, so the
  maximum is used.
- `Adj_Track_Count` — subtracts with `sbb ax,0` into the high word.

---

## 3. `forparse.inc` — `/U` switch registration

Three hunks:

1. `Command_Control` count bumped `db 13 → db 14` (`ShipDisk`) and
   `db 12 → db 13` (otherwise).
2. A pointer appended after `Autotest`:

	```asm
		dw	Switch_U_Control		;/U unconditional format
	```

3. The table entry, inserted before `Switch_F_Control`:

	```asm
	Switch_U_Control label byte
		dw	None				;
		dw	None				;
		dw	Switch_Buffer			;
		dw	No_Value			;
		db	1				;
		db	"/U",0				;
	```

Consistency check: 14 switch-pointer `dw` entries versus the declared counts
14 / 13 — matches dos4-core.

---

## 4. `forinit.asm` — `/U` consumed as a no-op

Inserted at the `$$IF71` block:

```asm
	cmp	Switch_Buffer.Switch_Pointer,offset Switch_U_Control.Keyword
	JNE	$$IF71a
	   mov	   Switch_U_Control.Keyword,20h 	; consume the switch
	;   /U needs no action: FORMAT never leaves data clusters in a state that
	;   an unconditional format would have to destroy (findings-04 A.2).
	$$IF71a:
```

Verified byte-identical to dos4-core (`diff` exit 0).

> **Editor's note.** This file is LF-only (0 CRLF, 1254 LF) despite being a DOS
> source, and its CP437 high-bit bytes make `read_file` refuse it as "binary".
> Edits must preserve bare LF or the diff will not apply.

---

## 5. `msfor.asm` — switch-mask relaxation

Three mask tests dropped switches that `/U` would otherwise collide with:

```asm
	test	switchmap, not (SWITCH_V or SWITCH_S or Switch_Backup or SWITCH_SELECT)
...
	test	SwitchMap, not (SWITCH_N or SWITCH_T or SWITCH_V or SWITCH_S or Switch_Backup)
...
	test	SwitchMap, not (SWITCH_1 or SWITCH_N)
	jnz	Bad_NT_Combo
	test	SwitchMap, not (SWITCH_S or Switch_Backup)
```

---

## 6. 2.88 MB (extended density) support — added

The previous revision of this document recorded 2.88 MB media as deliberately
unsupported. That is no longer true; this section replaces the old
"Deliberately not changed" note for 2.88 MB. The added geometry is 80
cylinders, 2 heads, 36 sectors per track, 512 bytes per sector, 5760 total
sectors (2,949,120 bytes).

Four pieces of work were required.

### 6.1 `forswtch.inc` — a size flag

`Size_2880 equ 0080h` was added after `Size_1440` (`0040h`). `0080h` was the
next free bit in the `SizeMap` byte; nothing else in the tree used it.

### 6.2 `forparse.inc` — the `/F:2880` spellings

Six `Switch_Size_Value` entries were appended, all tagging `Size_2880`:
`2880`, `2880K`, `2880KB`, `2.88`, `2.88M`, `2.88MB`. The string count byte in
the `Switch_Size_Value` header changed from `db 27` to `db 33` (27 pre-existing
entries plus these six). Getting this byte wrong silently truncates the search
list and leaves the new spellings unrecognised, so it is worth calling out.

The parser path is unchanged: `SysParse` returns the entry's `Item_Tag` in
`Switch_String_Buffer.Switch_String_Item_Tag`, and `forinit.asm` ORs it into
`SizeMap` (`or SizeMap,al`). No `forinit.asm` edit was required, which also
means the CP437 / bare-LF constraints on that file were not disturbed.

### 6.3 `msfor.asm` — `Other_Drives` and a fixed BPB

`Size_To_Switch` dispatches by device type. 2.88 MB media only makes sense on
a drive the driver reports as `DEV_OTHER`, which is the same bucket DOS already
uses for 1.44 MB. `Other_Drives` therefore gained a `Size_2880` test **ahead of**
the `Size_1440` test:

```
test SizeMap,Size_2880
JZ   no_2880
or   SwitchMap,Switch_T+Switch_N
mov  TrackCnt,80
mov  NumSectors,36
```

The synthetic `/T:80 /N:36` pair then flows through the existing switch matrix:
`Setup_Stuff` copies `NumSectors` into `BPB_SectorsPerTrack` and `TrackCnt` into
`DP_Cylinders`, and `Check_Switch_8_B` / `Check_T_N` validate the pair. Because
`/F` rejects any user-supplied `/1 /4 /8 /N /T` before `Size_To_Switch` runs,
the synthetic switches cannot trip the "incompatible parameters" check.

The BPB itself is *not* left to `Calc_Total`. A `BPB2880` template was added
next to `BPB720`:

```
BPB2880 a_BPB <512, 1, 1, 2, 240, 2*36*80, 0F0h, 23, 36, 2, 0, 0, 0, 0>
```

and `Check_720` copies it into `deviceParameters.DP_BPB` when `Size_2880` is
set, jumping straight to `EndSwitchCheck` exactly as the 720 KB case does.

The numbers are not arbitrary. `Calc_Total`'s FAT arithmetic
(`clusters*2/512 + 1`) is a single pass and cannot converge on a consistent
layout for this geometry, so the fixed template supplies the answer:

| quantity | value |
| --- | --- |
| total sectors | 5760 |
| sectors per cluster | 1 |
| reserved sectors | 1 |
| number of FATs | 2 |
| root entries | 240 |
| directory sectors | 240 × 32 ÷ 512 = 15 |
| sectors per FAT | 23 |
| start sector | 1 + 2×23 + 15 = 62 |
| data clusters | (5760 − 62) ÷ 1 = 5698 |
| FAT bytes needed | 5698 × 2 = 11396 = 22.25 → 23 sectors |

That layout is self-consistent **and** exceeds `BIG_FAT_THRESHOLD` (4086
clusters), which matters because `SetfBigFat` — not `Calc_Total` — decides
which file-system string the boot sector advertises ("FAT12   " vs
"FAT16   "). An earlier draft of this change used 2 sectors per cluster, which
gives only 2860 clusters: self-consistent as a FAT16 size but *below* the
threshold, so `SetfBigFat` would have stamped the volume "FAT12" while the FAT
was 16-bit. Keep the 1-sector-per-cluster layout.

### 6.4 `msfor.asm` — `Calc_Total` FAT width

Independently of the 2.88 MB template, `Calc_Total` used to compute a FAT12
size unconditionally (`clusters × 3 ÷ 2 ÷ 512 + 1`). It now divides the total
by `SectorsPerCluster`, compares the cluster count against `BIG_FAT_THRESHOLD`,
and picks either the old FAT12 formula or a FAT16 formula
(`(clusters + 2) × 2 ÷ 512 + 1`). This is what makes a `/T`/`/N` combination
that lands above 4086 clusters produce a correctly sized FAT even when no
fixed template applies. Existing sizes are unaffected: 1.44 MB is 2880
clusters and 1.2 MB is 2400 clusters, both under the threshold, so both still
take the FAT12 path and yield exactly the same sector counts as before.

### 6.5 `format.asm` — `DiskTable` needs no 2.88 row

`DiskTable` is consulted only by `Set_BPB_Info`, and only when the driver
reports `BPB_NumberOfFATs == 0`; a real 2.88 MB drive reports 2. The table's
first row is a deliberate catch-all for everything up to 32680 sectors, and the
scan stops at the first row whose sector count is ≥ the disk size, so a 2.88 MB
disk would match that row and be given a FAT12 layout — but only on the
pathological zero-FAT driver. Adding a 1680h row would not fix that: any
threshold low enough to match 5760 sectors would also capture 320/360/720/1200
/1440 KB media, since the scan walks downward. The reasoning is recorded as a
comment above `DiskTable` rather than as a table change.

**`/U` semantics.** The switch is accepted and consumed, but performs no extra
work. FORMAT never leaves data clusters in a form that an unconditional format
would have to erase, so the observable behaviour is identical to a normal
format.

**`SetfBigFat`.** Untouched, and still the authority for the FAT12/FAT16
label. It promotes any BPB with a non-zero `BPB_BigTotalSectors+2` to big-FAT,
and only the sub-32 MB case falls through to the 4086-cluster threshold. The
2.88 MB template was chosen so that it exceeds that threshold (see §6.3).

**`Relative_Sector_High` guards.** Two pre-existing guards at
`format.asm:622` and `format.asm:650` (this tree only) are retained. They
address a different overflow and are the only remaining diff against
dos4-core's `format.asm`.

---

## 7. What this does and does not achieve

**Achieved.** Volumes with more than 65535 sectors now compute correctly. 2048
MB is 4,194,304 sectors, well past the old wrap point, and the wrap was the
defect that broke large-media formatting. The first-track rounding, the total
track count, the track counters, the logical-sector calculation and the
percent-complete calculation are all 32-bit end to end.

**Still bounded, outside FORMAT.** FORMAT does not invent a geometry; it reads
`BPB_TotalSectors` / `BPB_BigTotalSectors` / heads / sectors-per-track from the
device driver through `GetDeviceParameters`. A volume larger than the driver
reports cannot be formatted regardless of arithmetic width. Separately, DOS 4's
FAT16 ceiling (~2 GB at 32 KB clusters) lives in the filesystem, not in the
track loop, and is not addressed by this port.

---

## 8. Verification performed

For the `2c6501a` port:

- `git show 2c6501a` diff read in full; all nine hunks present.
- `Phase2Initialisation` compared against dos4-core: byte-identical.
- `Divide_32x32` register contract (`SI:DI ÷ DX:CX → AX`) matches its sole
  call site.
- `grep` audit: no remaining 16-bit-only reference to `tracksLeft` or
  `tracksPerDisk`.
- `forinit.asm` diff against dos4-core: exit 0 (identical).
- `forparse.inc`: 14 switch pointers against declared 14 / 13.
- Whole-tree build via `Makefile.AI` / `dosbuild.sh` produced
  `build/FORMAT.COM` (23,051 bytes).

For the 2.88 MB work:

- `Size_2880` is defined once (`forswtch.inc`) and used in exactly three
  places: the six `forparse.inc` table entries, the `Other_Drives` dispatch and
  the `Check_720` BPB copy.
- `Switch_Size_Value` count byte audited: 27 original entries plus 6 new = 33,
  matching `db 33`.
- BPB arithmetic re-derived independently (§6.3 table); the chosen layout is
  the only self-consistent FAT16 geometry at 5760 sectors with 1 sector per
  cluster, and its 5698 clusters exceed `BIG_FAT_THRESHOLD` (4086) so
  `SetfBigFat` agrees with the `FAT16   ` string in the boot sector.
- Regression check on existing sizes: 1440 KB → 2880 clusters and 1200 KB →
  2400 clusters, both below the threshold, so `Calc_Total` still takes the FAT12
  path and produces unchanged sector counts.
- `$$IF` label numbering audited; `$$IF54` is unique in `msfor.asm`.
- `msfor.asm` was assembled with the MASM 5.10 binary shipped in the tree
  (`src/tools/masm.exe`) under DOSBox-X, headless
  (`SDL_VIDEODRIVER=dummy`), invoked as
  `masm msfor.asm,msfor.obj,nul,msfor.lst`. Result: 0 warnings, 2 severe
  errors, both at lines 1310 (`MESOFS`) and 1330 (`SYSMSG`) and both caused
  only by a temporary empty `BOOT.CL1` stub — that file is generated by
  `src/cmd/format/makefile` from `$(boot)\boot.cl1` and is not in the tree.
  No diagnostic falls anywhere in the edited regions (`BPB2880` 182-193,
  `Check_720` 2.88 branch 589-620, `Set_BPB` 621-680, `Other_Drives`
  945-1003), so every 2.88 MB edit to `msfor.asm` is syntactically valid.
  The stub has been removed again.
- **Not yet done:** a full `dosbuild.sh` / `mkit.bat` build, which would
  regenerate the real `boot.cl1` message file and produce a new
  `FORMAT.COM`. The other changed files (`format.asm`, `forinit.asm`,
  `forswtch.inc`) have not been assembled individually.
