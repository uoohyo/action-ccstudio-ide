# Release propagation and verification

A release is ready only after all three stages below are verified for the same
selected CCS version. A version-check run, result-sync run, or README badge
alone is not a substitute for a successful build.

| Stage | Required evidence | Incomplete state |
|---|---|---|
| Docker | Version image pushed; pull/test result and image digest recorded; version marked available in upstream docs | Missing installer, failed build/push, or unavailable image |
| Action | Full-version tag and Release exist; tagged Dockerfile pins the selected version; expected Action code revision is present | Missing tag/Release or older Action implementation |
| Sample | Main commit contains the selected workflow; Debug and Release builds and expected fresh artifacts pass | Maintenance push failed, workflow absent, pending or failed build |

## Triggers and normal delays

- Docker availability is sourced from [docker-ccstudio-ide](https://github.com/uoohyo/docker-ccstudio-ide)
  `docs/versions.md`. A documentation update does not directly dispatch this Action.
- Action reconciliation runs on main pushes, manual dispatch, repository dispatch,
  and Sunday 04:17 UTC. GitHub schedules can be delayed or disabled; a schedule is not a completion guarantee.
- [action-ccstudio-ide-sample](https://github.com/uoohyo/action-ccstudio-ide-sample) has a separate maintenance schedule
  and manual trigger. Do not assume Action completion starts sample maintenance immediately.
- Without manual intervention, propagation can span separate weekly cycles. Record
  each stage as pending, failed, or verified rather than presenting a single green status.

## Explicit recovery procedure

1. Select one toolchain version and inspect its upstream build/push evidence.
   Resolve installer access and distribution requirements before a licensed build.
2. After the upstream image is verified available, run this repository's
   `Sync CCS Versions` workflow once through Actions → Run workflow.
   Check `version-sync-results` and the step summary. Any failed operation fails the run.
3. Confirm the full tag's Dockerfile and Action implementation, then run the sample
   repository's maintenance workflow. Its remote push must succeed, not only its dry-run.
4. Select the corresponding sample workflow and verify both configurations at the
   intended main SHA, including their output artifacts.
5. Record the version, image digest, Action tag/commit, sample commit, and run URLs
   together. Mark the release complete only when no required stage is missing.

This procedure describes operator actions; it does not automatically dispatch or
publish anything. Credential changes, deployments, and cross-repository automation
must follow the repository owner's approval and least-privilege requirements.

## Retry and tag safety

- Automatic reconciliation preserves existing full toolchain-version tags. It does
  not repoint them to newer Action code. Publishing a new revision or deliberately
  republishing selected existing refs requires a separate owner decision and tests.
- Missing Releases and aliases are repaired even with no new toolchain version.
- Existing valid aliases are not rewritten. Alias updates use a remote ref lease;
  conflicting publishers cause a visible failure instead of silent overwriting.
- Any full-version failure prevents alias movement for that run. Retry after the
  cause is resolved; do not create substitute tags or claim a partial run succeeded.
- The workflow concurrency group serializes reconciliation. The tests use local
  bare Git repositories and mocked GitHub responses, not production tags.

## Local regression checks

```sh
python3 -m unittest discover -s tests -v
bash -n entrypoint.sh
```

These tests validate runtime argument/failure handling and sync control flow. They
do not install vendor tools or prove production credentials and registry availability.
