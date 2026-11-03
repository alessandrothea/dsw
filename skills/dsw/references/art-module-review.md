# Reviewing an art module for crash and silent-data risks

A checklist for analyzers/producers that dump trigger or MC data into trees. Use it when
reviewing a module, or after a crash shows the module is fragile. Apply fixes in order.
After each group: `dsw build`, then rerun the job over all events and check for
`status 0`. Preserve the output tree layout unless a change is explicitly agreed. Say in
the commit message when you change it.

## Crash risks (fix first)

1. **Unchecked pointer lookups.** Helpers that return `art::Ptr` (e.g. a backtracker's
   "find SimChannel for channel") return an invalid Ptr when nothing is found. Check it
   (`if (!ptr) ...`) before use; emit sentinel values on a miss.
2. **`map.at()` on data-dependent keys** (track IDs, truth blocks, TPC sets, generator
   names). Use `find()`. On a miss, fill `INVALID_*` sentinels and continue: a missing
   piece of metadata must never abort the event.
3. **Service lookups returning pointers** (`ParticleInventoryService::TrackIdToParticle_P`
   etc.): null-check before dereferencing, and cache per-ID results instead of calling the
   service twice per element.
4. **Associations:** take producer labels from fcl (no hardcoded `"largeant"`), build
   `FindManyP` with the full `InputTag` (label:instance:process), and check `isValid()`
   before `.at(i)`.
5. **Provenance probing** (`provenance()->parameterSet().get<...>()`): use
   `get_if_present` or defaulted gets. One producer with a different pset must not kill
   the job.
6. **Feature coupling:** if feature A needs data built by feature B (e.g. backtracking
   needs truth maps from the MCTruth dump), either build that data whenever A is on, or
   reject the combination in the constructor with a clear `cet::exception`.

## Silent wrong data

7. **Integer IDs stored as integers** in row structs, not `float`. Changing the type
   changes the tree schema (flag it).
8. **No narrowing:** row fields must be at least as wide as the product fields they copy
   (`uint8_t` ← `uint16_t` silently truncates). Copy real values; don't hardcode
   `version = 2` or `flag = 0`.
9. **Loud fallbacks:** a missing per-tool configuration (e.g. window offsets) should give
   `mf::LogWarning` **once per tag**, not `std::cout` per record. Better: validate in the
   constructor.
10. **Config coupling:** parameters needed only by an optional feature should have a
    default or be validated when the feature is enabled, not required unconditionally.
11. **Unsupported inputs:** if only some collection types are supported (e.g. TPC TPs),
    reject the others explicitly instead of writing misaligned branches.

## Maintenance

12. Remove dead code (`if (x && false)`, unused sets, commented-out alternatives).
13. Move per-element allocations out of inner loops (helpers built once per collection).
14. Fix misleading exception text (wrong type names, misordered tag fields). Throw
    `cet::exception("<Module>")`; log with `mf::Log*`, not `std::cout`.
15. In `endJob`, don't `Write()` objects TFileService already owns (duplicate `name;1`/`;2`).
16. Build regexes and other per-job objects once (member/constructor), not per event.
17. Initialise every member (`TTree* t = nullptr;`, flags, doubles in data structs).

## Verify

1. `dsw build` is clean (the build uses `-Werror`).
2. The job over all events gives `Art has completed and will exit with status 0`.
3. Entry counts per tree match the pre-fix baseline. Rows that used to crash now carry
   sentinels.
4. Spot-check physics branches (fractions in [0,1], IDs ≥ 0 or sentinel).
5. Add a configuration that exercises the new guards (e.g. a feature combination that
   should now be rejected) and record the command and the message.
