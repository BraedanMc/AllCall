# AllCall

Bash-first orchestration for mouse WGS cohorts: one YAML config, one germline samplesheet, and thin wrappers around [nf-core](https://nf-co.re/) viralintegration, Sarek (SV + SNP), and viralmetagenome.

Workflow design: [`docs/plans/2026-10-20-wgs-pipeline-workflow.md`](docs/plans/2026-10-20-wgs-pipeline-workflow.md).

## Requirements

- `bash`, `curl`, `yq` (YAML queries), `python3` (virus FASTA merge only)
- Java 17+ (for Nextflow; not installed here)
- Docker or Apptainer/Singularity (`container_profile` in config)
- `samtools` and `kraken2-build` on `PATH` for CDS filtering, sex checks, and Kraken2 DB build

## Configure

1. Copy and edit [`example.config.yaml`](example.config.yaml) (`scratch_root`, `samplesheet`, `container_profile`). nf-core pipeline names and `-r` revisions are pinned in [`bin/pipelines.env`](bin/pipelines.env), not in the YAML.
2. Cohort sheet: `sample`, `fastq_1`, `fastq_2` (optional `lane`). See [`samplesheets/cohort.csv.example`](samplesheets/cohort.csv.example).
3. Create `ref/virus/local/` and add optional extra viral `.fa` / `.fasta` files before setup.

## Setup → check → run

```bash
chmod +x bin/*.sh
./bin/setup.sh example.config.yaml
./bin/check.sh example.config.yaml
./bin/run_cohort.sh --config example.config.yaml --run-name cohort01
```

Dry-run (prints four `nextflow run … -resume` commands and writes `running` in the matrix):

```bash
./bin/run_cohort.sh --config example.config.yaml --dry-run
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
