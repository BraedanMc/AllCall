# Config and sample sheet

Archived 2026-10-20. Execute this plan on its own. Do not start the later plans from here.

## Goal

Create the Python package skeleton, load one versioned YAML config, and expand a simple germline sample sheet into the FASTQ sheets for viralintegration, sarek SV, and viralmetagenome. Prove it with pytest. GitHub Actions runs those tests on every push and pull request.

No network. No Nextflow. No reference files downloaded.

## Depends on

Nothing. This plan creates the package other plans extend.

## Do not do

- Download genomes, virus FASTAs, or Nextflow.
- Build a Kraken2 database, infer sex, filter BAMs, write the status matrix, or launch pipelines.
- Generate the sarek SNP sheet. That sheet needs filtered BAMs and inferred sex, which do not exist yet.
- Add site Nextflow workaround configs. `nextflow_configs` stays an empty list in the example.
- Commit, unless the user asks.

If a test needs a file on disk, write a tiny fixture. Do not call UCSC or GitHub.

## Package layout

Python 3.11. Package name `allcall`. Sources live in `src/allcall/`.

Create:

- `pyproject.toml` with a `allcall` console script pointing at `allcall.cli:main`, and a `dev` extra containing `pytest`
- `src/allcall/__init__.py`
- `src/allcall/errors.py`
- `src/allcall/config.py`
- `src/allcall/samplesheet.py`
- `src/allcall/cli.py`
- `example.config.yaml` at the repository root
- `tests/test_config.py`
- `.github/workflows/test.yml`
- `.gitignore`

Dependencies: `pyyaml` and `pydantic` v2. Use pydantic for the config model so missing keys fail with a field name, not a stack trace.

## Project root and paths

The project root is the directory that contains the config file. Every relative path in the config is resolved against that directory. Absolute paths are kept as written.

`example.config.yaml` therefore lives at the repository root, not under `config/`.

## Config

`example.config.yaml` must contain this content. Later plans read these same keys. Do not rename them.

```yaml
scratch_root: /scratch.global/bmcc
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: samplesheets/cohort.csv
results_dir: results
references:
  fasta_url: https://hgdownload.soe.ucsc.edu/goldenPath/mm39/bigZips/mm39.fa.gz
  fasta_gz: ref/mm39/mm39.fa.gz
  fasta: ref/mm39/mm39.fa
  fasta_md5: 41ace1b7157b98b393746aef5d1287a8
  gtf_url: https://hgdownload.soe.ucsc.edu/goldenPath/mm39/bigZips/genes/mm39.ncbiRefSeq.gtf.gz
  gtf_gz: ref/mm39/mm39.ncbiRefSeq.gtf.gz
  gtf: ref/mm39/mm39.ncbiRefSeq.gtf
  gtf_md5: 25e15ef5bdd7afc6d3447a757e5fa487
virus:
  bundled_url: https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/VIRUS_INSERTION_FINDING_LIB_SUPPLEMENT/virus_db.fasta
  bundled_fasta: ref/virus/ctat_virus_db.fasta
  local_dir: ref/virus/local
  merged_fasta: ref/virus/viral.fasta
  dedup_report: ref/virus/dedup.tsv
kraken2_db: ref/kraken2/mm39
pipelines:
  viralintegration:
    name: nf-core/viralintegration
    revision: "0.1.1"
    enabled: true
  sarek:
    name: nf-core/sarek
    revision: "3.10.0"
    enabled: true
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    name: nf-core/viralmetagenome
    revision: "1.2.0"
    enabled: true
nextflow:
  version: "25.10.7"
  bin: opt/nextflow
  home: opt/nxf-home
container_profile: apptainer
sex_xy_min_ratio: 0.1
nextflow_configs: []
```

`load_config(path) -> Config` returns a pydantic model with paths already resolved. `scratch_root` may be absolute or relative. Relative scratch roots resolve against the project root so tests do not need `/scratch.global`.

`work_dir(config, name) -> Path` returns `scratch_root / work_dirs[name]`. Unknown `name` raises `AllCallError`.

Validation rules:

- `container_profile` is `docker` or `apptainer`.
- `sex_xy_min_ratio` is a float in `(0, 1]`. Store it. Do not use it.
- Pipeline `revision` values are non-empty strings. Sarek requires `tools_sv` and `tools_snp`.
- Each entry in `nextflow_configs` must exist. An empty list is valid.
- MD5 fields match `^[0-9a-f]{32}$`.
- Do not contact the URLs. They are stored data.

`AllCallError` is the only exception CLI code catches. Include the field or column name in the message.

## Sample sheet

Input CSV header. Required columns: `sample`, `fastq_1`, `fastq_2`. Optional column: `lane`. Any other column, including `patient`, `sex`, or `status`, is an error. This cohort is germline only.

Row rules:

- `sample` is non-empty and contains no whitespace.
- `fastq_1` and `fastq_2` are both required and end with `.fastq.gz` or `.fq.gz`.
- If `lane` is absent on every row, assign `1`.
- If any row of a sample has `lane`, every row of that sample must have a distinct `lane`.
- A repeated `(sample, lane)` pair is an error.
- The CLI checks that both FASTQ paths exist. Library code takes `check_exists: bool` so unit tests can use fake paths.

Write sheets with `write_sheets(config, dest_dir, check_exists) -> dict[str, Path]`. Skip a pipeline whose `enabled` flag is false. Create `dest_dir` if needed.

Sarek SV columns, in this order:

```csv
patient,sex,status,sample,lane,fastq_1,fastq_2
```

`patient` equals `sample`. `sex` is `NA`. `status` is `0`. Paths are absolute.

Viralintegration and viralmetagenome columns, in this order:

```csv
sample,fastq_1,fastq_2
```

One input row becomes one output row. Lanes of the same sample stay as separate rows with the same `sample` value. Paths are absolute. Do not write a sarek SNP sheet.

## CLI

```text
allcall validate --config example.config.yaml
allcall sheets --config example.config.yaml --outdir runs/sheets
```

`validate` exits 0 and prints the four resolved work directories, one per line: `viralintegration=<path>` and the same for `sarek_sv`, `sarek_snp`, `viralmetagenome`.

`sheets` writes the CSVs and prints their paths. Expected validation failures exit 2 and print one line to stderr. Do not print a traceback for `AllCallError`.

## Tests

Write tests in `tests/test_config.py`. That is the only test module for this plan. Pytest collects it from the repository root. GitHub Actions runs `pytest` once; do not add more workflows.

Two tests, and no more:

1. `test_sheets_expand_germline_cohort` builds a temp config and a two-row CSV in `tmp_path`, calls `write_sheets`, and checks the three FASTQ sheets: sarek has `patient=sample`, `sex=NA`, `status=0`, and the other two sheets are `sample,fastq_1,fastq_2` with absolute paths.
2. `test_unexpected_column_is_rejected` adds a `status` column and expects `AllCallError`.

No network. Do not add a test per validation rule. The other rules in this plan are implemented and checked by reading the code, not by a test each.

GitHub Actions workflow `.github/workflows/test.yml`, named `test`:

- Trigger on `push` and `pull_request`.
- `ubuntu-latest`, Python 3.11.
- `pip install -e ".[dev]"`
- `pytest`
- No extra services and no cache of reference data.

## gitignore

Ignore `__pycache__/`, `.pytest_cache/`, `*.egg-info/`, `.venv/`, `opt/`, `ref/`, `results/`, `runs/`. Do not ignore `example.config.yaml` or `tests/`.

## Acceptance criteria

- `pip install -e ".[dev]"` and `pytest` pass with no network. `tests/test_config.py` contains only the two tests named above.
- `allcall validate --config example.config.yaml` exits 0.
- `allcall sheets` writes only the three FASTQ sheets, with `sex=NA` and `status=0`.
- The example config contains the UCSC URLs, MD5s, pipeline revisions, and Nextflow version exactly as written above, so later plans can rely on those names.
