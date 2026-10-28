# LLM handoff: implement k-mer GWAS workflow

This document is for an **automated agent** (or human) cloning the AllCall repo on branch **`feature/kmer-gwas-workflow`** and finishing deployment of the 20-sample WGS k-mer GWAS workflow. Read it end-to-end before editing code.

## Goal

Run [Voichek kmersGWAS](https://github.com/voichek/kmersGWAS) on **20 paired-end WGS samples**, using:

- **Raw FASTQs** on UMN HiPerGator scratch: **`/scratch.global/bmcc/`** (same convention as [`example.config.yaml`](../example.config.yaml) `scratch_root`)
- **Sample sheets and phenotype inputs** in this repo under **`input/kmer-gwas/`** (see [`input/README.md`](../input/README.md))
- **Orchestration scripts** under **`workflows/kmer-gwas/`** (adapted from [viannam/K-mer-GWAS-pipeline](https://github.com/viannam/K-mer-GWAS-pipeline))

Do **not** wire this into `bin/run_cohort.sh` unless explicitly requested.

## Critical: layout may differ in your checkout

The paths below describe **this** AllCall branch. Your target repo may use different roots (`src/`, `pipelines/`, monorepo layout, etc.).

**Rule:** Preserve **behavior** (params YAML, staging, KMC → table → GWAS, SLURM/container), not necessarily every folder name.

Whenever you change paths, names, or steps to fit the host repo, **append a dated entry** to [`kmer-gwas-implementation-adjustments.md`](kmer-gwas-implementation-adjustments.md). That file is the audit trail for the next agent.

## Data locations (AllCall)

| Data | Where | Notes |
|------|--------|--------|
| WGS FASTQ pairs | `/scratch.global/bmcc/...` | Listed in [`input/kmer-gwas/kmer_gwas.samples.csv`](../input/kmer-gwas/kmer_gwas.samples.csv); replace `PLACEHOLDER_FASTQ` with the real subdirectory under scratch |
| Phenotype files | `input/kmer-gwas/phenotypes/*.pheno` | Voichek format: `sample_id<TAB>numeric_value` per line; sample order must match the samplesheet |
| Phenotype index | `input/kmer-gwas/kmer_gwas.phenos.tsv` | Tab-separated: `phenotype_name`, `pheno_file` (path relative to repo root or absolute) |
| KMC / GWAS scratch | `/scratch.global/bmcc/kmer-gwas/<run_name>/` | Staging symlinks, KMC DBs, k-mer table (large) |
| GWAS results | `results/kmer-gwas/<run_name>/` | Gitignored; keep off scratch if you want long-term retention in the repo tree |
| Reference FASTA | `ref/hg38/hg38.fa` | After AllCall `./bin/setup.sh`; optional for association, used for post-GWAS mapping |

Do not commit multi-gigabyte FASTQs into `input/` or the git repo.

## Reference layout (this branch)

```text
AllCall/
  input/
    README.md
    kmer-gwas/
      kmer_gwas.samples.csv      # fastq paths → /scratch.global/bmcc/...
      kmer_gwas.phenos.tsv
      phenotypes/trait1.pheno
  workflows/kmer-gwas/
    README.md
    config/kmer_gwas.params.yaml
    bin/stage_inputs.sh
    bin/run_kmer_gwas.sh
    bin/pilot_kmc_one_sample.sh
    bin/map_significant_kmers.sh
    bin/kgwas_lib.sh
    bin/install_vendor.sh
    vendor/README.md             # Voichek zip + viannam clone instructions
    docs/container-and-deps.md
    docs/pilot-one-sample.md
  docs/
    kmer-gwas-llm-handoff.md     # this file
    kmer-gwas-implementation-adjustments.md
    plans/2026-10-28-kmer-gwas-20-wgs.md
```

## Step-by-step implementation checklist

### 0. Clone and branch

```bash
git clone git@github.com:BraedanMc/AllCall.git
cd AllCall
git checkout feature/kmer-gwas-workflow
```

If the branch name differs, use the branch that contains `workflows/kmer-gwas/`.

### 1. Read existing artifacts (do not reinvent)

1. [`workflows/kmer-gwas/README.md`](../workflows/kmer-gwas/README.md) — operator summary  
2. [`docs/plans/2026-10-28-kmer-gwas-20-wgs.md`](plans/2026-10-28-kmer-gwas-20-wgs.md) — archived plan  
3. [`workflows/kmer-gwas/vendor/README.md`](../workflows/kmer-gwas/vendor/README.md) — UF hardcoding in upstream `kmers_01.sh`  
4. [`workflows/kmer-gwas/docs/container-and-deps.md`](../workflows/kmer-gwas/docs/container-and-deps.md) — Linux / Apptainer / bare metal  

If your repo moved these files, update this handoff **and** the adjustments log.

### 2. Install vendor tools (Linux amd64)

On an HPC login node:

```bash
chmod +x workflows/kmer-gwas/bin/*.sh
workflows/kmer-gwas/bin/install_vendor.sh
curl -L -o /tmp/kmersGWAS.zip \
  https://github.com/voichek/kmersGWAS/releases/download/v0.3-beta/v0_3_beta.zip
unzip -d workflows/kmer-gwas/vendor/kmersGWAS /tmp/kmersGWAS.zip
```

Confirm `tools.*` paths in [`workflows/kmer-gwas/config/kmer_gwas.params.yaml`](../workflows/kmer-gwas/config/kmer_gwas.params.yaml) match the unpacked tree.

**Adjustment:** If binaries live in a module or container only, set `container.enabled: true` and document the image in the adjustments log; point `tools.kmc` at in-container paths or use `PATH`.

### 3. Configure params YAML

Edit [`workflows/kmer-gwas/config/kmer_gwas.params.yaml`](../workflows/kmer-gwas/config/kmer_gwas.params.yaml):

| Key | Action |
|-----|--------|
| `run_name` | Replace `PLACEHOLDER_RUN_NAME` (e.g. `cohort20_v1`) |
| `project_root` | Repo root on HPC, or leave placeholder (scripts default to repo root) |
| `samplesheet` / `phenotype_sheet` | Should point at `input/kmer-gwas/...` unless you relocated `input/` |
| `fastq_staging_dir`, `work_dir` | Under `/scratch.global/bmcc/kmer-gwas/<run_name>/` |
| `slurm.account`, `slurm.partition` | Valid for your allocation |
| `container.image` | Real `.sif` or disable container on bare metal |
| `kmers_gwas.min_data_points` | Keep **≤ 20** (default here: 15) |

Log any renames of keys or files in the adjustments doc.

### 4. Fill inputs in `input/kmer-gwas/`

1. **Samplesheet** — Replace `PLACEHOLDER_FASTQ` in every `fastq_1` / `fastq_2` path with the directory under `/scratch.global/bmcc/` where R1/R2 files live. Use **absolute** paths. Verify all 20 pairs exist on scratch.  
2. **Phenotypes** — Replace placeholder zeros in `input/kmer-gwas/phenotypes/trait1.pheno` with real measurements. One row per sample; **same sample IDs and order** as the CSV. Add more traits by creating new `.pheno` files and rows in `kmer_gwas.phenos.tsv`.  
3. **Phenotype matrices** — If traits arrive as CSV/TSV matrices (samples × traits), convert to one Voichek `.pheno` per trait (two columns: sample, value) and record the conversion command in the adjustments log.

### 5. Reference genome

```bash
./bin/setup.sh example.config.yaml   # or site config with species: human
```

Ensure `ref/hg38/hg38.fa` exists. Post-GWAS Bowtie2 mapping is optional (`post_gwas.enabled`).

### 6. Pilot one sample (required before 20× WGS)

Follow [`workflows/kmer-gwas/docs/pilot-one-sample.md`](../workflows/kmer-gwas/docs/pilot-one-sample.md):

```bash
workflows/kmer-gwas/bin/pilot_kmc_one_sample.sh --sample SAMPLE01 \
  --params workflows/kmer-gwas/config/kmer_gwas.params.yaml
```

Record disk and runtime; extrapolate for 20 samples. If quota is insufficient, document subsampling or regional FASTQ strategy in the adjustments log.

### 7. Dry-run full workflow

```bash
workflows/kmer-gwas/bin/run_kmer_gwas.sh \
  --params workflows/kmer-gwas/config/kmer_gwas.params.yaml --dry-run
```

Inspect generated script under `work_dir` on scratch. Fix path errors before removing `--dry-run`.

### 8. Execute

```bash
workflows/kmer-gwas/bin/run_kmer_gwas.sh \
  --params workflows/kmer-gwas/config/kmer_gwas.params.yaml
```

Default `executor: slurm` submits via `sbatch`. For interactive debugging on a compute node: `--local`.

### 9. Optional post-GWAS

1. Export significant k-mer list from GWAS output.  
2. Set `post_gwas.enabled: true` and `post_gwas.significant_kmers_list` in params.  
3. Run mapping (included at end of pipeline script when enabled) or [`bin/map_significant_kmers.sh`](../workflows/kmer-gwas/bin/map_significant_kmers.sh).

### 10. Validate and document

- Confirm outputs under `results/kmer-gwas/<run_name>/gwas/`.  
- Append **all** structural/path changes to [`kmer-gwas-implementation-adjustments.md`](kmer-gwas-implementation-adjustments.md).  
- Update [`workflows/kmer-gwas/README.md`](../workflows/kmer-gwas/README.md) if the operator-facing steps changed.

## Common adjustments (expect these)

- **`input/` elsewhere** — e.g. `data/cohort/`; update params + handoff + adjustments log.  
- **Different scratch root** — still use `/scratch.global/bmcc` for raw WGS unless the site documents otherwise; change `fastq_staging_dir` / `work_dir` consistently.  
- **No SLURM** — set `executor: local` and run on a large Linux node; log in adjustments.  
- **Mac checkout** — implementation and KMC runs happen on HPC only; Mac is for editing sheets in `input/`.  
- **Duplicate samplesheets** — legacy copies under `workflows/kmer-gwas/samplesheets/` may exist; **canonical** sheets for this project are under `input/kmer-gwas/`.

## Success criteria

- [ ] 20 samples staged from scratch FASTQs  
- [ ] KMC + kmersGWAS completes on HPC  
- [ ] At least one phenotype in `input/kmer-gwas/phenotypes/` tested  
- [ ] Adjustments log updated if anything differed from this handoff  
- [ ] Pilot metrics recorded before full cohort run  

## References

- [voichek/kmersGWAS](https://github.com/voichek/kmersGWAS)  
- [kGWASflow / PubMed 37976215](https://pubmed.ncbi.nlm.nih.gov/37976215/) (alternative packaging; not used as driver here)  
- [viannam/K-mer-GWAS-pipeline](https://github.com/viannam/K-mer-GWAS-pipeline)  
