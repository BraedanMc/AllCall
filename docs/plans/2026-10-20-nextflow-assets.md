# Nextflow assets

Archived 2026-10-20. Execute this plan on its own after the config plan is in the tree. It does not need the genome files.

## Goal

Install a pinned Nextflow binary inside the project and pull the three pinned nf-core revisions into a project-local Nextflow home. Add a check that the binary and the pulled revisions are present. Unit tests mock every download and every subprocess. GitHub Actions must not install Nextflow or pull pipelines.

## Depends on

`docs/plans/2026-10-20-config-and-samplesheet.md` is implemented. These must already exist:

- `load_config` exposing `nextflow.version`, `nextflow.bin`, `nextflow.home`
- Pipeline records for `viralintegration` `0.1.1`, `sarek` `3.10.0`, and `viralmetagenome` `1.2.0`, each with `name` and `enabled`
- `AllCallError` and the existing CLI

If those are missing, stop. Do not invent a second config schema.

## Do not do

- Run any pipeline, including `-profile test` or `-stub`.
- Pass `-c` site configs. Leave `nextflow_configs` unread. Those files are coming later.
- Install Java, Docker, or Apptainer. Java is checked and then reported missing.
- Download genomes or the virus FASTA.
- Write samplesheets or the status matrix.
- Commit `opt/` or the Nextflow cache.
- Commit, unless the user asks.

## Files to add

- `src/allcall/nextflow_assets.py`
- `tests/test_nextflow_assets.py`

Add subcommands to the existing CLI.

## Commands

```text
allcall nextflow install --config example.config.yaml
allcall nextflow pull --config example.config.yaml
allcall nextflow check --config example.config.yaml
```

Exit 0 on success. Exit 2 with one stderr line on `AllCallError`.

## Install

Download this URL, with `{version}` taken from the config:

```text
https://github.com/nextflow-io/nextflow/releases/download/v{version}/nextflow
```

Write it to `nextflow.bin` (default `opt/nextflow`) via a `.partial` file, then rename and set the executable bit. Create parent directories. Running `install` again replaces the binary when `nextflow -version` does not report the pinned version, and skips the download when it does.

Before `pull` or `check`, run `java -version`. Accept stderr or stdout. Require a major version of 17 or newer. If `java` is missing or older, raise `AllCallError` with the text `Java 17+ is required and is not installed by this package`. Do not download a JDK.

## Environment

`nextflow_env(config) -> dict` returns a copy of the current environment plus:

- `NXF_HOME` set to the resolved `nextflow.home`
- `NXF_DISABLE_CHECK_LATEST` set to `true`

Every Nextflow subprocess this package starts uses that environment and the project-local binary, not a `nextflow` found on `PATH`.

## Pull

For each pipeline with `enabled: true`, run:

```text
<project nextflow> pull <pipeline name> -r <revision>
```

Examples of the three argv lists:

```text
opt/nextflow pull nf-core/viralintegration -r 0.1.1
opt/nextflow pull nf-core/sarek -r 3.10.0
opt/nextflow pull nf-core/viralmetagenome -r 1.2.0
```

Skip disabled pipelines. If a pull exits non-zero, stop and raise `AllCallError` with the pipeline name, revision, and return code. Do not continue to the next pipeline after a failure.

`check` does not pull. It fails unless:

- the binary exists and is executable
- `nextflow -version` output contains the pinned version string
- Java 17+ is available
- each enabled pipeline's revision is present under `NXF_HOME`

Treat a revision as present when a directory or file under `NXF_HOME` contains both the pipeline name with the slash replaced by a separator Nextflow actually uses, and the revision. Inspect one real `NXF_HOME` layout while implementing, then lock that relative path in the test with a fixture directory. Do not guess in the test; the test builds the fixture to match the code.

## Tests

Write one test in `tests/test_nextflow_assets.py`. Do not add another test module, and do not add a GitHub Actions workflow. The workflow from the config plan already runs `pytest`.

`test_pull_uses_pinned_revisions` monkeypatches subprocess. It asserts the three argv lists below, that each call uses the project-local binary, and that `NXF_HOME` is the config's Nextflow home. No network and no Java in this test.

Do not add tests for the installer, the Java version parser, or the check command. Those behaviors are specified above and reviewed by running the commands outside CI.

## Acceptance criteria

- `pytest` passes with no network. `tests/test_nextflow_assets.py` contains only `test_pull_uses_pinned_revisions`. The earlier tests still pass.
- `allcall nextflow check` exits 2 before install, and the message names the missing binary or Java.
- Outside CI, after `install` and `pull`, `check` exits 0.
- `opt/nextflow -version` reports `25.10.7` when `NXF_HOME` is `opt/nxf-home`.
- A second `install` and a second `pull` do not download the binary again. `pull` may still contact Nextflow's cache; that is acceptable. The binary download must not repeat.
- Nothing under `opt/` is committed.
