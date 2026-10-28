# Vendor dependencies

## viannam/K-mer-GWAS-pipeline

SLURM-oriented shell entrypoint and documentation (not a complete binary bundle in GitHub).

```bash
git clone --depth 1 https://github.com/viannam/K-mer-GWAS-pipeline.git \
  workflows/kmer-gwas/vendor/K-mer-GWAS-pipeline
```

Or run [`../bin/install_vendor.sh`](../bin/install_vendor.sh) from the k-mer GWAS workflow root.

### Hardcoded paths in `kmers_01.sh`

The upstream script is a **UF HiPerGator template**, not a portable runner:

| Line / setting | Value | Change for your site |
|----------------|-------|----------------------|
| `#SBATCH --account` | `mresende` | Set in [`config/kmer_gwas.params.yaml`](../config/kmer_gwas.params.yaml) `slurm.*`; use [`bin/run_kmer_gwas.sh`](../bin/run_kmer_gwas.sh) instead of raw `kmers_01.sh` |
| `#SBATCH --qos` | `mresende-b` | Your partition/QOS |
| `WORKDIR` | `/blue/mresende/share/viannam/Kmers` | `work_dir` in params |
| FASTQ paths | `/orange/mresende/viannam/02.fasta/...` | Staged FASTQs via [`bin/stage_inputs.sh`](../bin/stage_inputs.sh) |
| `module load ...` | R, gemma, gcc, bamtools | Use container or modules on your cluster |
| `KMERS_BIN` | `${WORKDIR}/bin` | `tools.kmers_bin` in params (Voichek release) |
| KMC | `${WORKDIR}/external_programs/kmc_v3` | `tools.kmc` in params or `PATH` inside container |
| `--mac 5` | default MAC filter | Overridden by `kmers_gwas.minor_allele_count` (2 for n=20) |

Upstream `kmers_01.sh` also mixes array-job snippets with cohort steps; AllCall’s [`bin/run_kmer_gwas.sh`](../bin/run_kmer_gwas.sh) generates a parameterized pipeline from params YAML.

## voichek/kmersGWAS binaries

The viannam repo **does not ship** `bin/` or `external_programs/` on GitHub. Download the release and unpack under `vendor/kmersGWAS/`:

```bash
curl -L -o /tmp/kmersGWAS.zip \
  https://github.com/voichek/kmersGWAS/releases/download/v0.3-beta/v0_3_beta.zip
unzip -d workflows/kmer-gwas/vendor/kmersGWAS /tmp/kmersGWAS.zip
```

Point `tools.kmers_bin`, `tools.kmc`, and `tools.kmers_gwas_py` in params at the unpacked paths (Linux amd64 only).

Contents of `vendor/kmersGWAS/` are gitignored; only this README is tracked.
