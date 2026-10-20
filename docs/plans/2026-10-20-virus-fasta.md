# Virus FASTA

Archived 2026-10-20. Execute this plan on its own after the config plan is in the tree. It does not need the mouse genome or Nextflow.

## Goal

Build the viralintegration virus FASTA during setup: the FASTA bundled with that pipeline, plus every sequence in a local directory, deduplicated by sequence name. Local sequences win on a name clash. Prove it with tiny fixtures. GitHub Actions must not download the Broad Institute file.

## Depends on

`docs/plans/2026-10-20-config-and-samplesheet.md` is implemented. These must already exist:

- `load_config` exposing `virus.bundled_url`, `virus.bundled_fasta`, `virus.local_dir`, `virus.merged_fasta`, `virus.dedup_report`
- The example `bundled_url` of `https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/VIRUS_INSERTION_FINDING_LIB_SUPPLEMENT/virus_db.fasta`
- `AllCallError` and the existing CLI

If those are missing, stop. Do not recreate the config schema.

## Do not do

- Run viralintegration.
- Download mm39 or install Nextflow.
- Recurse into subdirectories of `local_dir`.
- Silently drop a duplicate name inside the local directory or inside the bundled file.
- Commit the merged FASTA or the downloaded CTAT file. `ref/` is gitignored.
- Commit, unless the user asks.

## Files to add

- `src/allcall/virus_fasta.py`
- `tests/test_virus_fasta.py`

Add subcommands to the existing CLI.

## Commands

```text
allcall virus build --config example.config.yaml
allcall virus check --config example.config.yaml
```

Exit 0 on success. Exit 2 with one stderr line on `AllCallError`. `build` downloads the bundled file when it is missing, writes the merged FASTA and the report, then checks. `check` never downloads. It fails if the merged FASTA or the report is missing. It also fails if rebuilding in memory from the already-downloaded bundled file and `local_dir` would change either output. That second check is how a stale merge is caught without a network call.

## Merge rules

1. Download `bundled_url` to `bundled_fasta` via a `.partial` file. Replace an existing bundled file only when it is absent. Do not invent an MD5; the upstream file has no checksum in the config. If the download is interrupted, delete the partial.
2. Read FASTA records from `bundled_fasta`, then from files directly inside `local_dir` whose names end with `.fa`, `.fasta`, `.fa.gz`, or `.fasta.gz`. Sort local filenames so the merge order is stable. Ignore other files. A missing `local_dir` is an error. An empty `local_dir` is valid.
3. The sequence name is the first whitespace-delimited token of the header, without a leading `>`.
4. A name repeated inside the bundled file is an error. A name repeated across local files is an error. Do not keep the first one.
5. A name present in both sources keeps the local sequence and the local header. The report marks that name `replaced`.
6. A name only in the bundled file is `kept`. A name only in the local files is `added`.
7. Write `merged_fasta` as uncompressed FASTA. One record per name. Header is `>` plus the winning header's first token only. Sequence lines are wrapped at 60 characters.
8. Order records with bundled names first, in their original order, then added local names in filename-then-file order.
9. Write `dedup_report` as a TSV with header `name`, `source`, `status`. `source` is `bundled` or the local filename. `status` is `kept`, `added`, or `replaced`. Sort rows by `name`.

`build` is idempotent. A second run with the same inputs leaves both outputs byte-identical and does not download again.

## Tests

Write one test in `tests/test_virus_fasta.py`. Do not add fixture files or another test module, and do not add a GitHub Actions workflow. The workflow from the config plan already runs `pytest`.

`test_merge_keeps_adds_and_replaces` writes three small FASTA files into `tmp_path`: bundled `KeepMe=ACGT` and `OverrideMe=AAAA`, local `NewVirus=CCCC`, and local `OverrideMe=TTTT`. Monkeypatch the downloader to copy the bundled file. Assert the merged sequences are `ACGT`, `TTTT`, and `CCCC`, and that the report marks `kept`, `replaced`, and `added`. No network.

Do not add tests for duplicates, gzip inputs, idempotence, or the check command.

## Acceptance criteria

- `pytest` passes with no network. `tests/test_virus_fasta.py` contains only `test_merge_keeps_adds_and_replaces`. The earlier tests still pass.
- `allcall virus check --config example.config.yaml` exits 2 before a build, naming the missing merged FASTA.
- Outside CI, `allcall virus build --config example.config.yaml` writes `ref/virus/ctat_virus_db.fasta`, `ref/virus/viral.fasta`, and `ref/virus/dedup.tsv`.
- A local sequence whose name matches a bundled sequence replaces it, and the report says `replaced`.
- A second `build` does not download and does not change the merged file bytes.
- Those `ref/virus/` outputs are not committed.
