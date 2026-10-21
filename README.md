# AllCall

Bash-first orchestration for mouse WGS cohorts: a **site** YAML for per-run settings, a versioned **pin** manifest for references and pipeline revisions, one germline samplesheet, and thin wrappers around [nf-core](https://nf-co.re/) viralintegration, Sarek (SV + SNP), and viralmetagenome.

Workflow design: [`docs/plans/2026-10-20-wgs-pipeline-workflow.md`](docs/plans/2026-10-20-wgs-pipeline-workflow.md).

## Requirements

`./bin/setup.sh` installs Bash 5, Java 17, `yq`, `samtools`, and `kraken2-build` into `opt/` from the versions in [`config/pin.yaml`](config/pin.yaml). Later scripts use `opt/env.sh` and do not need those tools from a module or the system `PATH`. Bash 5 is included because the scripts use it, and macOS still ships Bash 3.

Still required on the machine:

- `bash` (any version) and `curl`, so setup can start and download the rest
- `python3`, for the virus FASTA merge only
- Docker or Apptainer/Singularity (`container_profile` in site config). Setup checks for one of these and does not install it.

Install or refresh only the host tools:

```bash
./bin/setup.sh --tools-only
```

## Configure (two files)

| File | Who edits | Contents |
|------|-----------|----------|
| [`config/pin.yaml`](config/pin.yaml) | Maintainers on reference/pipeline bumps | mm39 URLs and MD5s, virus asset URLs/paths, Kraken2 DB path, nf-core **name + revision** per pipeline, Nextflow version/bin/home |
| [`site.config.yaml`](site.config.yaml) (copy from [`example.config.yaml`](example.config.yaml)) | You per site/run | `scratch_root`, `work_dirs`, `samplesheet`, `results_dir`, pipeline **enabled** flags and Sarek tool choices, `container_profile`, optional `nextflow_configs` overlays |

`bin/lib.sh` loads **`config/pin.yaml` first**, then your site file (`ALLCALL_PIN` overrides the pin path). Keys should not overlap; site values win if they do.

1. Copy and edit `site.config.yaml` (`scratch_root`, `samplesheet`, `container_profile`, enable/disable pipelines).
2. Cohort sheet: `sample`, `fastq_1`, `fastq_2` (optional `lane`). See [`samplesheets/cohort.csv.example`](samplesheets/cohort.csv.example).
3. Create `ref/virus/local/` and add optional extra viral `.fa` / `.fasta` files before setup.

## Setup → check → run

```bash
chmod +x bin/*.sh
./bin/setup.sh site.config.yaml
./bin/check.sh site.config.yaml
./bin/run_cohort.sh --config site.config.yaml --run-name cohort01
```

Dry-run (prints four `nextflow run … -resume` commands and writes `running` in the matrix):

```bash
./bin/run_cohort.sh --config site.config.yaml --dry-run
```

Status matrix: `results/<run-name>/matrix.tsv`.

## Scripts

| Script | Role |
|--------|------|
| `bin/setup.sh` | References, virus merge, Nextflow install/pull, Kraken2 DB |
| `bin/check.sh` | Same gates as setup, no downloads |
| `bin/write_sheets.sh` | Simple sheet → pipeline CSVs |
| `bin/run_cohort.sh` | Cohort driver (VI, SV, VM parallel; CDS + SNP when ready) |
| `bin/merge_virus_fasta.sh` | CTAT + local virus FASTA merge |
| `bin/cds_bed.sh` | CDS intervals from GTF (+ flank) |

## Tests

```bash
./tests/smoke.sh
```

CI runs `shellcheck` (when available) and fixture smoke tests only — no UCSC downloads, no Nextflow install.
