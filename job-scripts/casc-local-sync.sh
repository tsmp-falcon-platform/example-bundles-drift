#!/usr/bin/env bash

set -euo pipefail

export PERFORM_VALIDATION="${PERFORM_VALIDATION:-true}"
export PERFORM_BOOTSTRAP="${PERFORM_BOOTSTRAP:-false}"
export BUNDLEUTILS_BOOTSTRAP_UPDATE="${BUNDLEUTILS_BOOTSTRAP_UPDATE:-false}"
export BUNDLEUTILS_BOOTSTRAP_PROFILE="${BUNDLEUTILS_BOOTSTRAP_PROFILE:-}"
export MAKE_COMMAND=( make -f "Makefile" )

run_export_my_bundle() {
  export MY_BUNDLE
  if [ -n "${1:-}" ]; then
    MY_BUNDLE=$1
  else
    MY_BUNDLE=$(bundleutils find-bundle-by-url)
  fi
}

run_handle_drift() {
  echo "Handling drift branch..."
  "${MAKE_COMMAND[@]}" auto/git-handle-drift
}

run_handle_and_checkout_drift() {
  run_handle_drift
  run_checkout_drift
}

run_checkout_drift() {
  echo "Checking out drift branch..."
  "${MAKE_COMMAND[@]}" auto/git-checkout-drift
}

run_main_target() {
  echo "Running main target..."
  "${MAKE_COMMAND[@]}" auto/all
}

run_audit_target() {
  echo "Running audit target..."
  "${MAKE_COMMAND[@]}" auto/audit
}

run_git_diff_commit_check_and_push() {
  echo "Running a git diff to check..."
  "${MAKE_COMMAND[@]}" auto/git-diff 2> /dev/null || "${MAKE_COMMAND[@]}" auto/git-commit
  echo "Everything should have been committed, failing if diff found..."
  "${MAKE_COMMAND[@]}" git-diff
  echo "Pushing changes..."
  "${MAKE_COMMAND[@]}" git-push
}

run_sync_steps() {
  run_export_my_bundle
  if [ "${1:-}" = "drift" ]; then run_handle_and_checkout_drift; fi
  run_main_target
  run_git_diff_commit_check_and_push
}

run_bootstrap_steps() {
  local myBundle=''
  myBundle=$(bundleutils find-bundle-by-url -v '.*' || true)
  if [ -z "$myBundle" ]; then
    echo "First bootstrap call needed in case bundle bundle in question doesn't exist yet..."
    "${MAKE_COMMAND[@]}" bootstrap
  fi
  run_export_my_bundle "$myBundle"
  run_handle_drift
  run_checkout_drift
  echo "Second bootstrap call needed because we do a hard reset of the branch..."
  "${MAKE_COMMAND[@]}" bootstrap
  run_main_target
  run_git_diff_commit_check_and_push
}

run_audit_steps() {
  echo "Expecting two directories:
  BUNDLES_DIR (currently set to ${BUNDLES_DIR:-} and should be the CWD)
  AUDIT_DIR (currently set to ${AUDIT_DIR:-})"
  # if base dir is not set to BUNDLES_DIR, then fail
  curr_base_dir=$(basename "$(pwd)")
  if [ "$curr_base_dir" != "$BUNDLES_DIR" ]; then
    echo "ERROR: Current directory is not the BUNDLES_DIR, failing..."
    exit 1
  fi

  export BUNDLEUTILS_AUDIT_TARGET_BASE_DIR="../$AUDIT_DIR"
  export BUNDLEUTILS_USE_PROFILE='audit'
  run_export_my_bundle
  run_audit_target

  # sanity checking the bundle dir for changes, failing if diff found
  echo "Everything should have been committed, failing if diff found..."
  "${MAKE_COMMAND[@]}" git-diff

  # Change make commands to point to the Makefile in the BUNDLES_DIR
  MAKE_COMMAND=( make -f "../$BUNDLES_DIR/Makefile" )
  # Use the bundle-profiles.yaml file in the BUNDLES_DIR to find the bundle
  export BUNDLEUTILS_AUTO_ENV_FILE="../$BUNDLES_DIR/bundle-profiles.yaml"
  # Set the BUNDLE_PROFILES to empty to avoid trying to add the non-existent bundle-profiles.yaml file to git
  export BUNDLE_PROFILES=''
  cd "../$AUDIT_DIR"
  run_export_my_bundle
  run_git_diff_commit_check_and_push
}

echo "Running version..."
bundleutils version || true
case "${JOB_NAME:-}" in
  *"-drift")
    echo "Running in drift mode..."
    run_sync_steps drift
    ;;
  *"-direct")
    echo "Running in direct mode..."
    run_sync_steps
    ;;
  *"-bootstrap")
    echo "Running in bootstrap mode..."
    PERFORM_BOOTSTRAP=true
    run_bootstrap_steps
    ;;
  *"-update")
    echo "Running in update mode..."
    PERFORM_BOOTSTRAP=true
    BUNDLEUTILS_BOOTSTRAP_UPDATE=true
    run_bootstrap_steps
    ;;
  *"-audit")
    echo "Running in audit mode..."
    BUNDLES_DIR=${BUNDLES_DIR:-"bundles"}
    AUDIT_DIR=${AUDIT_DIR:-"audit"}
    run_audit_steps
    ;;
  *)
    echo "ERROR: Please provide a JOB_NAME with -drift or -direct or -bootstrap or -update."
    exit 1
    ;;
esac

