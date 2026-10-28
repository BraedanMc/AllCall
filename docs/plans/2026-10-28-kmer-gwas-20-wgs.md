# k-mer GWAS workflow (20 WGS samples)

Archived snapshot 2026-10-28. Implemented under [`workflows/kmer-gwas/`](../workflows/kmer-gwas/).

Standalone wrapper around [viannam/K-mer-GWAS-pipeline](https://github.com/viannam/K-mer-GWAS-pipeline) (Voichek [kmersGWAS](https://github.com/voichek/kmersGWAS)) for 20 full-genome WGS samples. Params YAML + CSV/TSV sheets; not wired into AllCall’s Nextflow cohort driver. Reference hg38 (`ref/hg38/hg38.fa`) is for optional post-GWAS k-mer placement.

## Implemented artifacts

- [`workflows/kmer-gwas/config/kmer_gwas.params.yaml`](../workflows/kmer-gwas/config/kmer_gwas.params.yaml) — placeholders and n=20 thresholds (`min_data_points: 15`, `minor_allele_count: 2`)
- [`workflows/kmer-gwas/samplesheets/`](../workflows/kmer-gwas/samplesheets/) — 20-sample CSV + pheno index
- [`workflows/kmer-gwas/bin/`](../workflows/kmer-gwas/bin/) — `stage_inputs.sh`, `run_kmer_gwas.sh`, `pilot_kmc_one_sample.sh`, `map_significant_kmers.sh`, `kgwas_lib.sh`, `install_vendor.sh`
- [`workflows/kmer-gwas/vendor/README.md`](../workflows/kmer-gwas/vendor/README.md) — viannam `kmers_01.sh` hardcoded path table + Voichek zip install
- [`workflows/kmer-gwas/docs/container-and-deps.md`](../workflows/kmer-gwas/docs/container-and-deps.md) — Apptainer vs bare metal
- [`workflows/kmer-gwas/docs/pilot-one-sample.md`](../workflows/kmer-gwas/docs/pilot-one-sample.md) — one-sample KMC pilot

## Logical flow

Reference is optional for association; required only for Bowtie2 post-GWAS when `post_gwas.enabled: true`.

Staging → per-sample KMC (canonical + non-canonical) → strand info → cohort k-mer table → kinship → `kmers_gwas.py` per phenotype → optional k-mer mapping to hg38.

## Scale

20 × full hg38 WGS: plan terabytes of scratch for KMC; run [`pilot_kmc_one_sample.sh`](../workflows/kmer-gwas/bin/pilot_kmc_one_sample.sh) before the full cohort.

## Optional later

kGWASflow-style QC/HTML report; Nextflow per-sample KMC; pin file `config/kmer_gwas.pin.yaml`.
