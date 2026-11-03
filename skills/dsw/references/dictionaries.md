# ROOT dictionary and streamer mismatches

## Recognise it

- `lar` aborts (134) with `corrupted size vs. prev_size`, `malloc(): ...`, or segfaults (139),
  with a backtrace through `TBasket::DropBuffers`/`ReadBasketBuffers`/`GetEntry`,
  `art::RootDelayedReader::getProduct_`, `Principal::getMany`. This often happens several
  events after the real damage.
- A data-product header (or `classes.h`/`classes_def.xml`) was edited after the last
  dictionary generation, or the input file was written before/after a dictionary change.

**Root cause pattern:** `build_dictionary()` re-runs rootcling only when the
**timestamps** of `classes.h`/`classes_def.xml` change. Editing only the product header
recompiles the dictionary `.o` from the *stale* generated `_dict.cpp`. Everything builds,
then I/O writes or reads records with the wrong layout. A checksum pinned in
`classes_def.xml` that matches the stale layout also silences art's mismatch check.

## Step 1: null test (is the file itself bad?)

```bash
dsw macro -q -l <abs>/read_all.log read_all <abs>/input.root      # Events tree
```

It prints `entry N ok` (flushed) per entry, then `ALL OK`. If plain ROOT crashes, **the
module is not the cause**: the file and/or the dictionary is.

## Step 2: file layout vs runtime layout

```bash
dsw macro streamer_cmp <abs>/input.root <fully::qualified::Class>
```

This prints the StreamerInfo as stored in the file and as loaded now (version, checksum,
size, element offsets and types). Red flags:
- same checksum, but different element lists (a stale checksum pinned in the XML);
- offsets/types that don't match the header;
- runtime `size` ≠ `sizeof` the header implies.

The class names in a file: list the streamer infos with a short PyROOT script
(`for si in f.GetStreamerInfoList(): print(si.GetName(), si.GetClassVersion(), si.GetCheckSum())`).

## Step 3: which layout does a checksum belong to?

Write each candidate layout (exact namespace, member names and types) to its own file:

```cpp
// old.h
namespace dunedaq::trgdataformats { struct TriggerActivityData { /* old members */ }; }
```

Then run one process per candidate (a name can only be declared once per process):

```bash
dsw macro --clean-room class_checksum <abs>/old.h dunedaq::trgdataformats::TriggerActivityData
dsw macro --clean-room class_checksum <abs>/new.h dunedaq::trgdataformats::TriggerActivityData
```

`--clean-room` hides the experiment dictionaries, so the declaration is not shadowed by
the real one. Without it, the macro refuses to run. The candidate whose checksum equals
the file's is the layout the file was written with. The new layout's checksum is the
honest value to pin.

## Step 4: is the build stale?

Compare mtimes of the generated dictionary and its inputs (`--time-style=full-iso`):

- generated: `$MRB_BUILDDIR/<pkg>/<path>/<target>_dict.cpp`, `<target>_dict_checked`,
  `$MRB_BUILDDIR/<pkg>/slf7.x86_64.<quals>/lib/lib<target>_dict_rdict.pcm`
- inputs: the product headers, `classes.h`, `classes_def.xml`

Find the dictionary targets with `dsw exec ninja -C <build dir> -t targets all`, then grep
for `_dict`. Generated files older than a header edit mean a stale dictionary.

## Fix (ask the user before editing `classes_def.xml` or deleting files)

1. **On a layout change:** bump `ClassVersion` (N → N+1) in `classes_def.xml` and set the
   **honest** checksum of the new layout (Step 3). Never re-pin the old checksum: it hides
   exactly this failure. Drop `<version>` entries for superseded layouts unless old files
   must stay readable.
2. **Force rootcling.** Either `touch` `classes.h` and `classes_def.xml` (cheap), or delete
   the generated `<target>_dict.cpp` and the `<target>_dict_checked` stamp in the build dir
   (definitive). Then `dsw build -q -l <log>`. The log must show
   `Generating dictionary files for target ...` and `Checking class versions ...`.
3. **Verify:** the `_rdict.pcm` mtime is fresh, and `dsw macro streamer_cmp <new file> <FQN>`
   runtime checksum/size/offsets match the header.

## Files written with a stale dictionary

They are corrupt **whatever their checksums say**: records were written for the wrong
layout. **Regenerate, don't repair:**
- keep the bad file as `<file>.broken`;
- rerun the producer stage (`dsw run -c <producer>.fcl -s <abs>/<prev stage>.root`), then
  every later stage. Start from the earliest stage produced after the header change.
- Prove it: `read_all` on the new file gives `ALL OK`, the original failing job runs all
  events with `status 0`, and the output trees look sane.

## Habits that prevent it

- After any data-product header edit, `touch classes.h classes_def.xml` before building.
- Every layout change: bump `ClassVersion` and pin the fresh checksum.
- After building: a quick `streamer_cmp` (runtime) to compare size/offsets with the header.
- Treat files written between a header change and the dictionary fix as suspect.
