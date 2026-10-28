# Pilot: one-sample KMC before 20× WGS

Run this on **Linux amd64** (HPC login or compute) after FASTQ paths in the samplesheet are real.

## Steps

1. Edit [`config/kmer_gwas.params.yaml`](../config/kmer_gwas.params.yaml):
   - `run_name`, `project_root`, `fastq_staging_dir`, `work_dir` (replace `PLACEHOLDER_*`).
   - `tools.kmc` pointing at Voichek-bundled KMC or `kmc` on `PATH` in a container.
2. Replace `PLACEHOLDER_DATA/...` in [`samplesheets/kmer_gwas.samples.csv`](../samplesheets/kmer_gwas.samples.csv) for at least one sample.
3. Stage and pilot:

```bash
cd /path/to/AllCall
chmod +x workflows/kmer-gwas/bin/*.sh
workflows/kmer-gwas/bin/pilot_kmc_one_sample.sh --sample SAMPLE01 \
  --params workflows/kmer-gwas/config/kmer_gwas.params.yaml
```

4. Record output:
   - `Elapsed_seconds`
   - `du -sh` on `workflows/kmer-gwas/scratch/<run_name>/pilot_kmc/SAMPLE01/`

## Extrapolation

Multiply pilot disk by **20** for a lower bound on per-sample KMC footprint (cohort filtering steps add more). Full-depth hg38 WGS often reaches **terabytes** cumulative scratch; adjust `kmc_min_count`, coverage, or regional FASTQs if the pilot exceeds quota.

## Full cohort

After the pilot looks acceptable:

```bash
workflows/kmer-gwas/bin/run_kmer_gwas.sh --params workflows/kmer-gwas/config/kmer_gwas.params.yaml --dry-run
workflows/kmer-gwas/bin/run_kmer_gwas.sh --params workflows/kmer-gwas/config/kmer_gwas.params.yaml
```

Use `--stage-only` to validate symlinks without KMC.
