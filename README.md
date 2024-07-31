# Example Bundles Drift

This is a template repository to be used as an example for the [bundleutils](https://github.com/tsmp-falcon-platform/ci-bundle-utils) tool.

## Makefile

A [Makefile](./Makefile) has been provided with some common tasks.

<!-- START makefile-doc -->
```bash
$ make help


Usage:
  make <target>

Targets:
  %/update-bundle        Run bundleutils update-bundle in the directory '%'
  %/fetch                Run bundleutils fetch in the directory '%'
  %/transform            Run bundleutils fetch in the directory '%'
  %/refresh              Run bundleutils fetch and transform in the directory '%'
  %/validate             Run validation steps in the directory '%'
  %/all                  Run all steps in the directory '%'
  %/git-diff             Run git diff in the directory '%'
  %/git-commit           Run git commit in the directory '%'
  %/git-create-branch    Creates a drift branch for the directory '%'
  %/deploy-cm            Deploy configmap from directory '%'
  %/check                Ensure a bunde exists in the directory '%'
  git-diff               Run git diff for the whole repository
  git-reset              Run git reset --hard for the whole repository
  find                   List all bundle dirs according to bundle pattern var 'BP'
  help                   Makefile Help Page
```
<!-- END makefile-doc -->