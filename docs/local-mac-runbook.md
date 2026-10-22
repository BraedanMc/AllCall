# Mac local cohort runbook

Human (hg38) viral integration on a Mac with Docker Desktop. Phase 1 runs **nf-core viralintegration** only; Sarek and viralmetagenome stay off until a **disk gate** passes.

## Prerequisites

- Docker Desktop running.
- Clone with `main` including `config/local.vi-only.config.yaml` and `data/README.md`.
- Scratch tree: `mkdir -p ~/Documents/projects/allcall/scratch data ref/virus/local`

## 1. Poll `data/` for FASTQs

Copy **two** paired-end `.fastq.gz` files into `data/` (see `data/README.md`). Ignore any `data/*.sh` helpers.

Poll every **3–5 minutes** until both files are present and **stable** (size unchanged between checks):

```bash
watch -n 180 'ls -lh data/*.fastq.gz 2>/dev/null; sleep 5; ls -lh data/*.fastq.gz 2>/dev/null'
```

When sizes match on two consecutive listings, proceed.

## 2. Cohort sheet (gitignored)

Copy the template and set real filenames (Mac worker fills `TBD` paths):

```bash
cp samplesheets/cohort.human.single.example.csv samplesheets/cohort.csv
# Edit fastq_1 / fastq_2 to match files under data/
```

`samplesheets/cohort.csv` is not committed.

## 3. Setup and check (skip Kraken on Mac)

```bash
./bin/setup.sh --skip-kraken config/local.vi-only.config.yaml
./bin/check.sh config/local.vi-only.config.yaml
```

Full reference download and Nextflow pulls require network and disk; Kraken2 build is skipped.

## 4. Phase 1 — viralintegration (real run)

```bash
./bin/run_cohort.sh --config config/local.vi-only.config.yaml --run-name mac-vi-01
```

Monitor Nextflow under `~/Documents/projects/allcall/scratch/nfVI` and cohort outputs under `results/mac-vi-01/`.

## 5. Disk gate before Sarek / viralmetagenome

Before enabling Sarek SV/SNP or viralmetagenome, confirm free space on the scratch volume (rule of thumb: **≥ 200 GB** free for a modest human WGS cohort; adjust for your FASTQ size).

```bash
df -h ~/Documents/projects/allcall/scratch
```

If the gate passes:

1. Copy `config/local.config.yaml` to `site.config.yaml` (or merge pipeline flags).
2. Set `pipelines.sarek.enabled` and/or `pipelines.viralmetagenome.enabled` to `true`.
3. Re-run `./bin/check.sh` and `./bin/run_cohort.sh` with a new `--run-name`.

If the gate fails, stop after phase 1 and archive VI results only.

## Reference configs

| File | Use |
|------|-----|
| `config/local.vi-only.config.yaml` | Phase 1: VI only, `samplesheets/cohort.csv` |
| `config/local.config.yaml` | Full local stack when disk allows |
| `samplesheets/cohort.human.single.example.csv` | Single-sample human template |
