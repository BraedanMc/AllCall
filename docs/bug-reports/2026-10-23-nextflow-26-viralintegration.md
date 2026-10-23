# Bug report: Nextflow 26.x blocks nf-core/viralintegration 0.1.1 via CLI and config parsing

**Status:** Workaround in AllCall — pin Nextflow **24.10.5** and pass cohort params with **`-c`** instead of **`-params-file`**.  
**Date:** 2026-10-23  
**Reporter:** AllCall project (Mac local cohort testing)  
**Suggested upstream:** [nextflow-io/nextflow](https://github.com/nextflow-io/nextflow/issues) and/or [nf-core/viralintegration](https://github.com/nf-core/viralintegration/issues)

## Summary

AllCall orchestrates several nf-core pipelines with one project-local Nextflow binary (`config/pin.yaml`). With **Nextflow 26.10.3**, **nf-core/viralintegration 0.1.1** fails before or during config load when we launch the same way that works on **24.10.5**. Because AllCall uses a **single** Nextflow version for every pipeline, we downgraded the pin to **24.10.5** for the whole cohort stack.

## Environment

| Component | Version |
|-----------|---------|
| Nextflow (failing) | 26.10.3 |
| Nextflow (working) | 24.10.5 build 5935 |
| Pipeline | nf-core/viralintegration **0.1.1** (`-r 0.1.1`) |
| Java | OpenJDK 17 |
| Host | macOS (Apple Silicon), Docker Desktop (`-profile docker`) |
| Launcher | `bin/run_cohort.sh` → `opt/nextflow run …` |

## Expected behavior

1. `nextflow run nf-core/viralintegration -r 0.1.1` with a user-supplied Groovy config fragment:

   ```groovy
   params {
     input = "/path/to/samplesheet.csv"
     outdir = "/path/to/out"
     fasta = "/path/to/hg38.fa"
     gtf = "/path/to/hg38.gtf"
     viral_fasta = "/path/to/viral.fasta"
   }
   ```

   should parse and launch the workflow (subject to resources).

2. Supplying that file via either **`-c`** or a documented params mechanism should be consistent across Nextflow minor versions used by nf-core.

## Observed behavior

### Failure A — `-params-file` with a `.config` params block (Nextflow 26)

AllCall initially generated `results/<run>/params/viralintegration.config` (Groovy `params { … }`) and invoked:

```bash
nextflow run nf-core/viralintegration -r 0.1.1 -resume \
  -work-dir <scratch>/nfVI \
  -params-file results/<run>/params/viralintegration.config \
  -profile docker \
  -c config/nextflow/local.config
```

On **26.10.3**, Nextflow rejected this combination (params file format / extension expectations). The run did not start.

**Workaround:** use **`-c`** for the generated params file (same Groovy content):

```bash
-c results/<run>/params/viralintegration.config
```

### Failure B — Config parsing on pipeline `nextflow.config` (Nextflow 26)

After adjusting the CLI, **26.10.3** still failed while parsing **viralintegration**’s bundled config (legacy nf-core helpers such as resource check functions in config scope — observed in logs as conflicts with stricter/newer config parsing in NF 26).

On **24.10.5**, the same revision **0.1.1** parses and executes (until resource limits, e.g. STAR `genomeGenerate` OOM on small Docker RAM).

## Impact on AllCall pipelines

All cohort `nextflow run` commands share `nf_cmd()` in `bin/run_cohort.sh` and the same `nextflow.version` pin:

| Pipeline | Revision | NF 26 impact |
|----------|----------|----------------|
| viralintegration | 0.1.1 | **Blocked** (CLI + config) |
| sarek (SV / SNP) | 3.10.0 | Same **launcher** issue if `-params-file` used; pipeline likely compatible with newer NF once CLI fixed |
| viralmetagenome | 1.2.0 | Same **launcher** issue |

We pin **24.10.5** globally so viralintegration can run; Sarek and viralmetagenome remain on supported NF versions.

## Steps to reproduce

1. Clone [AllCall](https://github.com/BraedanMc/AllCall) at a commit with `nextflow.version: "26.10.3"` and `-params-file` in `bin/run_cohort.sh`.
2. `./bin/setup.sh --skip-kraken config/local.vi-only.config.yaml`
3. `./bin/run_cohort.sh --config config/local.vi-only.config.yaml --run-name repro`

Compare with `nextflow.version: "24.10.5"` and `-c` for the generated params file.

## AllCall mitigation (merged via PR)

- `config/pin.yaml`: `nextflow.version: "24.10.5"`
- `bin/run_cohort.sh`: `-c "$params"` instead of `-params-file`
- `config/nextflow/local.config`: `singularity.enabled = false` so `-profile docker` is not overridden on Mac
- Optional `config/nextflow/local.apptainer.config` when `container_profile: apptainer`
- viralintegration params: `viral_fasta` (pipeline name), `max_cpus` / `max_memory` caps for local executor

## References

- Mac run log: project store `internal/mac-local-run-log.md` (attempts v1–v2: NF 26 CLI/config; v3+: resource limits on 24.10.5)
- Successful NF 24 launch example in local `.nextflow.log` (viralintegration 0.1.1, `-c` params + local overlay)

## Request

1. **Nextflow:** Clarify supported way to inject a Groovy `params { }` file from orchestrators in 26.x (`-c` vs `-params-file`), and whether legacy nf-core 0.1.x config patterns should still parse.
2. **nf-core/viralintegration:** Document minimum Nextflow version for 0.1.1, or release a revision tested on current Nextflow stable.
