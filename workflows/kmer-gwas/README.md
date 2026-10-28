# k-mer GWAS (20 WGS samples)

Standalone workflow around [Voichek kmersGWAS](https://github.com/voichek/kmersGWAS) and the SLURM template [viannam/K-mer-GWAS-pipeline](https://github.com/viannam/K-mer-GWAS-pipeline). Not part of [`bin/run_cohort.sh`](../../bin/run_cohort.sh).

**For an LLM implementing this on another machine:** start with [`docs/kmer-gwas-llm-handoff.md`](../../docs/kmer-gwas-llm-handoff.md) and log repo-specific changes in [`docs/kmer-gwas-implementation-adjustments.md`](../../docs/kmer-gwas-implementation-adjustments.md).

## Quick start

1. **Params** — edit [`config/kmer_gwas.params.yaml`](config/kmer_gwas.params.yaml) (`run_name`, SLURM, container).
2. **Samples** — edit [`input/kmer-gwas/kmer_gwas.samples.csv`](../../input/kmer-gwas/kmer_gwas.samples.csv); FASTQs on **`/scratch.global/bmcc/`**.
3. **Phenotypes** — [`input/kmer-gwas/phenotypes/`](../../input/kmer-gwas/phenotypes/) + [`input/kmer-gwas/kmer_gwas.phenos.tsv`](../../input/kmer-gwas/kmer_gwas.phenos.tsv).
4. **Vendor tools** — [`bin/install_vendor.sh`](bin/install_vendor.sh) + Voichek zip ([`vendor/README.md`](vendor/README.md)).
5. **Reference** — `./bin/setup.sh` → `ref/hg38/hg38.fa`.
6. **Pilot** — [`docs/pilot-one-sample.md`](docs/pilot-one-sample.md).
7. **Run** — `bin/run_kmer_gwas.sh --params config/kmer_gwas.params.yaml`.

```bash
chmod +x workflows/kmer-gwas/bin/*.sh
workflows/kmer-gwas/bin/run_kmer_gwas.sh --params workflows/kmer-gwas/config/kmer_gwas.params.yaml --dry-run
```

## Layout

| Path | Purpose |
|------|---------|
| `config/kmer_gwas.params.yaml` | Paths, k-mer/GWAS thresholds, SLURM, container |
| `input/kmer-gwas/` | Tracked samplesheet, pheno index, phenotype files |
| `samplesheets/` | Legacy examples (prefer `input/kmer-gwas/`) |
| `bin/stage_inputs.sh` | CSV → `sample_R{1,2}.fastq.gz` symlinks + `Sample-genotypes.txt` |
| `bin/run_kmer_gwas.sh` | Stage + generate/run pipeline (SLURM or local) |
| `bin/pilot_kmc_one_sample.sh` | Single-sample KMC timing/disk estimate |
| `bin/map_significant_kmers.sh` | Optional Bowtie2 mapping to hg38 |
| `vendor/` | viannam clone + user-provided Voichek binaries |
| `docs/container-and-deps.md` | Linux vs Mac, Apptainer, bare metal |

Outputs under `results/kmer-gwas/<run_name>/` (gitignored). Scratch under `/scratch.global/bmcc/kmer-gwas/<run_name>/`.

## Related

- Original method: [voichek/kmersGWAS](https://github.com/voichek/kmersGWAS)
- Snakemake alternative: [kGWASflow](https://github.com/akcorut/kGWASflow) ([PubMed 37976215](https://pubmed.ncbi.nlm.nih.gov/37976215/))
