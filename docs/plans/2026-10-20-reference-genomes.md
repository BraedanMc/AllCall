# Reference genome download

Archived 2026-10-20. Execute this plan on its own after the config plan is in the tree.

## Goal

Download the UCSC mm39 FASTA and NCBI RefSeq GTF into the project, verify their gzip MD5s, and decompress them to the paths in the config. Add a check command that does not download. Prove both with pytest using local fixtures. GitHub Actions must not contact UCSC.

## Depends on

`docs/plans/2026-10-20-config-and-samplesheet.md` is implemented. These must already exist:

- `src/allcall/config.py` with `load_config` and the `references` fields (`fasta_url`, `fasta_gz`, `fasta`, `fasta_md5`, `gtf_url`, `gtf_gz`, `gtf`, `gtf_md5`)
- `src/allcall/errors.py` with `AllCallError`
- `src/allcall/cli.py` with `main`
- `example.config.yaml` containing the URLs and MD5s from that plan

If any of those are missing, stop. Do not recreate the package or the config schema.

## Do not do

- Download or build a Kraken2 database.
- Build BWA, STAR, samtools, or GATK indexes. The pipelines build those themselves.
- Download the virus FASTA or Nextflow.
- Gunzip in place over a file whose stamp does not match. See the skip rules below.
- Change the pinned URLs or MD5s.
- Commit, unless the user asks.

## Files to add

- `src/allcall/references.py`
- `tests/test_references.py`

Wire two subcommands into the existing CLI. Do not replace `validate` or `sheets`.

## Commands

```text
allcall references download --config example.config.yaml
allcall references check --config example.config.yaml
```

`download` fetches anything missing or stale, then checks. `check` never fetches. Both exit 0 on success and exit 2 with one stderr line on `AllCallError`.

## Download rules

For the FASTA, and again for the GTF:

1. The MD5 in the config is the MD5 of the gzipped file, not the decompressed file.
2. Download `fasta_url` to `fasta_gz` plus a `.partial` suffix, then rename it onto `fasta_gz` only after the MD5 matches. Delete the partial and raise `AllCallError` naming the file and both checksums when it does not.
3. Write `fasta` + `.stamp` containing the gzip MD5 after a successful decompress. Decompress to a temporary file in the same directory, then rename.
4. Skip the download when `fasta_gz` exists and its MD5 matches the config.
5. Skip decompress when `fasta` exists and `fasta.stamp` equals the config MD5.
6. If `fasta_gz` exists but the MD5 does not match, delete it and download again.
7. If `fasta` exists but the stamp is missing or different, decompress again from the verified gzip.
8. Create parent directories as needed.

Use the stdlib (`urllib.request` and `gzip`) so CI does not need an HTTP library. Stream the body to disk. Set a 60-second timeout.

`check` fails when either decompressed file is missing, either stamp is missing or different from the config MD5, or either gzip is present but does not match its MD5. A missing gzip is acceptable for `check` when the decompressed file and stamp are valid.

## Tests

Write one test in `tests/test_references.py`. Do not add another test module, and do not add a GitHub Actions workflow. The workflow from the config plan already runs `pytest`.

`test_download_verifies_and_skips` builds a tiny gzip in `tmp_path`, points a temp config at it, and monkeypatches the downloader to copy that file. It checks the decompressed file and the stamp. It then calls download again and asserts the downloader was not called. No network.

The MD5 mismatch, missing-file, and CLI exit paths are part of the command behavior above. Do not write a test for each one.

## Acceptance criteria

- `pytest` passes with no network. `tests/test_references.py` contains only `test_download_verifies_and_skips`. The two config tests still pass.
- `allcall references check --config example.config.yaml` exits 2 before a real download, with a message that names the missing FASTA or GTF.
- After a real download, outside CI, `check` exits 0, `ref/mm39/mm39.fa` and `ref/mm39/mm39.ncbiRefSeq.gtf` exist, and both stamp files contain the config MD5s.
- Running `download` a second time does not fetch again.
- `ref/` stays gitignored. The gzipped genomes are not committed.
