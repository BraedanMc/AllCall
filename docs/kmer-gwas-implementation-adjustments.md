# k-mer GWAS: implementation adjustments log

**Maintainers:** Any agent or human implementing this workflow must append here when the repo layout, paths, or scripts diverge from [`kmer-gwas-llm-handoff.md`](kmer-gwas-llm-handoff.md) or [`workflows/kmer-gwas/`](../workflows/kmer-gwas/).

Use one dated section per change set. Do not delete prior entries.

---

## Template (copy for each change)

### YYYY-MM-DD — short title

- **Reason:** why the outline did not fit this repo
- **Change:** what was moved, renamed, or rewritten
- **Paths affected:** files or directories
- **Follow-up:** anything still broken or untested

---

## Initial scaffold (AllCall, 2026-10-28)

- **Reason:** n/a (baseline on `feature/kmer-gwas-workflow`)
- **Change:** Added `workflows/kmer-gwas/` scripts and params; cohort sheets and phenotypes under `input/kmer-gwas/`; scratch paths default to `/scratch.global/bmcc/kmer-gwas/<run_name>/`
- **Paths affected:** see handoff doc “Reference layout”
- **Follow-up:** Voichek binaries not vendored in git; viannam clone gitignored; run pilot on HPC before full cohort
