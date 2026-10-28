# Containers and dependencies (k-mer GWAS)

Archived workflow notes for [`workflows/kmer-gwas/`](../).

## Platform

| Environment | kmersGWAS binaries | Recommendation |
|-------------|-------------------|----------------|
| Linux HPC (amd64) | Voichek v0.3-beta in `vendor/kmersGWAS/` | Bare metal **or** Apptainer with binds |
| macOS (Apple Silicon) | Not supported natively | Run on HPC; use pilot only to validate staging paths locally |

AllCall’s Docker/Apptainer setup ([`README.md`](../../README.md)) covers **Nextflow nf-core** pipelines, not this workflow. Reuse the same **Apptainer on HPC** habit here.

## Bare metal (simplest on UF HiPerGator)

1. `./bin/install_vendor.sh` — clone viannam script template.
2. Unpack [voichek/kmersGWAS v0.3-beta](https://github.com/voichek/kmersGWAS/releases/download/v0.3-beta/v0_3_beta.zip) into `vendor/kmersGWAS/`.
3. `module load` or `conda` for **R ≥ 4**, **python2.7**, **GEMMA** if not using bundled `external_programs/gemma_*`.
4. Set `container.enabled: false` in [`config/kmer_gwas.params.yaml`](../config/kmer_gwas.params.yaml).
5. `executor: slurm` and fill `slurm.account`, `slurm.partition`.

Paths in params (`tools.kmers_bin`, `tools.kmc`, `tools.kmers_gwas_py`) must point at the unpacked Voichek tree.

## Apptainer (recommended when modules differ)

There is **no official** kGWASflow/kgwasflow SIF checked into AllCall. Build or pull one **linux/amd64** image that includes:

- `kmc`, GEMMA, Python 2.7, R + MASS/Mvnpermute/matrixcalc
- Voichek `bin/*` and `kmers_gwas.py` on `PATH` or at the paths in params

Example run pattern (image name is a placeholder):

```bash
apptainer exec --bind /scratch.global/youruser,/path/to/AllCall \
  /path/to/kmers-gwas.sif \
  bash workflows/kmer-gwas/bin/run_kmer_gwas.sh --params workflows/kmer-gwas/config/kmer_gwas.params.yaml --local
```

Set in params:

```yaml
container:
  enabled: true
  engine: apptainer
  image: /path/to/kmers-gwas.sif
```

[`bin/kgwas_lib.sh`](../bin/kgwas_lib.sh) wraps `apptainer exec` with `--bind ${PROJECT_ROOT}` when `kgwas_exec` is used (pilot KMC). The generated cohort script in `work_dir` currently runs **directly on the compute node**; extend the SLURM header in [`bin/run_kmer_gwas.sh`](../bin/run_kmer_gwas.sh) to wrap the whole pipeline in Apptainer if your site requires it.

## Small cohort (n = 20)

Defaults in Voichek `kmers_gwas.py` use `min_data_points: 30`. This workflow sets **`min_data_points: 15`** and **`minor_allele_count: 2`** in params—required for 20 WGS samples.

## Reference genome

GWAS steps do not read the reference. [`reference.fasta`](../config/kmer_gwas.params.yaml) defaults to AllCall **`ref/hg38/hg38.fa`** (relative to `project_root`) for optional post-GWAS mapping via [`bin/map_significant_kmers.sh`](../bin/map_significant_kmers.sh).

Run AllCall `./bin/setup.sh` once so `ref/hg38/hg38.fa` exists.

## Dependency summary

| Tool | In AllCall? | Get it |
|------|-------------|--------|
| yq | `opt/tools/bin/yq` after setup | `./bin/setup.sh --tools-only` |
| samtools | `opt/tools/bin/samtools` | post-GWAS BAM sorting |
| KMC / GEMMA / kmersGWAS | No | Voichek zip or Bioconda inside custom container |
| Snakemake | No | Not used in this workflow |
| Bowtie2 | No | Biocontainer or module; used only if `post_gwas.enabled: true` |
