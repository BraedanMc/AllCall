# Workflow inputs (tracked metadata only)

Large raw files stay on HPC scratch (`/scratch.global/bmcc/`). This directory holds **small, versioned inputs** for workflows: sample sheets, phenotype files, and phenotype index tables.

## k-mer GWAS

| Path | Purpose |
|------|---------|
| [`kmer-gwas/kmer_gwas.samples.csv`](kmer-gwas/kmer_gwas.samples.csv) | 20 samples; `fastq_*` columns point at FASTQs under `/scratch.global/bmcc/` |
| [`kmer-gwas/kmer_gwas.phenos.tsv`](kmer-gwas/kmer_gwas.phenos.tsv) | Maps trait name → phenotype file |
| [`kmer-gwas/phenotypes/`](kmer-gwas/phenotypes/) | Voichek-format phenotype files (`sample<TAB>value`) |

Do not commit multi-GB FASTQs here. Add only paths in the CSV.
