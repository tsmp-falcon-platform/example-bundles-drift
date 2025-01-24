.DEFAULT_GOAL		:=  help
SHELL						:=  /bin/bash
MAKEFLAGS				+= --no-print-directory
MKFILE_FILE			:=  $(abspath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR			:=  $(dir $(MKFILE_FILE))
GIT_ORIGIN			?=  origin
GIT_MAIN				?=  main
BUNDLE_PROFILES	?=  bundle-profiles.yaml
BOOTSTRAP_BASE	?=  bundles/controller-bundles
.ONESHELL:


.PHONY: bootstrap
bootstrap: ## Run bundleutils bootstrap according to the JENKINS_URL
	if [ "$${PERFORM_BOOTSTRAP:-}" == "true" ]; then \
		if [ -n "$${MY_BUNDLE:-}" ]; then \
			bundleutils bootstrap -s "$${MY_BUNDLE}"; \
		else \
			bundleutils bootstrap -S $(BOOTSTRAP_BASE); \
		fi; \
	else \
		echo "Skipping bootstrap due to PERFORM_BOOTSTRAP=false"; \
	fi

.PHONY: run/%/config
run/%/config: ## Run bundleutils config in the directory '%'
	cd $*
	bundleutils config

.PHONY: run/%/update-bundle
run/%/update-bundle: ## Run bundleutils update-bundle in the directory '%'
run/%/update-bundle: run/%/check
	bundleutils update-bundle -t $*

.PHONY: run/%/audit
run/%/audit: ## Run bundleutils audit in the directory '%'
run/%/audit: run/%/fetch
	cd $*
	bundleutils audit

.PHONY: run/%/fetch
run/%/fetch: ## Run bundleutils fetch in the directory '%'
	cd $*
	bundleutils fetch

.PHONY: run/%/transform
run/%/transform: ## Run bundleutils fetch in the directory '%'
	cd $*
	bundleutils transform

.PHONY: run/%/refresh
run/%/refresh: ## Run bundleutils fetch and transform in the directory '%'
run/%/refresh: run/%/fetch run/%/transform
	cd $*

.PHONY: run/%/ci-start
run/%/ci-start: ## Setup and start test-server according to the directory '%'
run/%/ci-start: run/%/check run/%/update-bundle
	cd $*
	bundleutils ci-setup
	bundleutils ci-start || { bundleutils ci-stop; exit 1; }

.PHONY: run/%/ci-validate
run/%/ci-validate: ## Run ci-validation for the directory '%'
run/%/ci-validate: run/%/check run/%/update-bundle
	cd $*
	bundleutils ci-validate

.PHONY: run/%/ci-stop
run/%/ci-stop: ## start test-server according to in the directory '%'
run/%/ci-stop: run/%/check
	cd $*
	bundleutils ci-stop

.PHONY: run/%/validate
run/%/validate: ## Run validation steps in the directory '%'
run/%/validate: run/%/check run/%/update-bundle run/%/ci-start
	cd $*
	bundleutils ci-validate || { bundleutils ci-stop; exit 1; }
	bundleutils ci-stop

.PHONY: run/%/all
run/%/all: ## Run all steps in the directory '%'
run/%/all: run/%/refresh
	if [ "$${PERFORM_VALIDATION:-}" == "false" ]; then echo "Skipping validation"; else $(MAKE) -f $(MKFILE_FILE) run/$*/validate; fi

.PHONY: run/%/git-diff
run/%/git-diff: ## Run git diff in the directory '%'
run/%/git-diff: run/%/check
	git add $* $(BUNDLE_PROFILES)
	git --no-pager diff --cached --exit-code $* $(BUNDLE_PROFILES)

.PHONY: run/%/git-commit
run/%/git-commit: ## Run git commit in the directory '%'
run/%/git-commit: run/%/check
	git commit -m "Update $$(basename $*) (version: $$(grep -oP 'version: \K.*' $*/bundle.yaml))" $* $(BUNDLE_PROFILES)

run/%/git-handle-drift: ## Creates or rebases drift branch for the directory '%'
	set -e
	DRIFT_BRANCH_NAME=$(GIT_MAIN)-$$(basename $*)-drift
	if git show-ref --quiet refs/remotes/$(GIT_ORIGIN)/$$DRIFT_BRANCH_NAME; then \
		$(MAKE) -f $(MKFILE_FILE) run/$*/git-rebase-drift; \
	else \
		$(MAKE) -f $(MKFILE_FILE) run/$*/git-create-drift; \
	fi

.PHONY: run/%/git-checkout-drift
run/%/git-checkout-drift: ## Checks out a drift branch for the directory '%'
run/%/git-checkout-drift: run/%/check
	set -e
	DRIFT_BRANCH_NAME=$(GIT_MAIN)-$$(basename $*)-drift
	git reset --hard && git clean --force -dfx
	git checkout $$DRIFT_BRANCH_NAME

.PHONY: run/%/git-create-drift
run/%/git-create-drift: ## Creates a drift branch for the directory '%'
run/%/git-create-drift: run/%/check
	set -e
	DRIFT_BRANCH_NAME=$(GIT_MAIN)-$$(basename $*)-drift
	git checkout -b $$DRIFT_BRANCH_NAME
	git push --set-upstream $(GIT_ORIGIN) $$DRIFT_BRANCH_NAME
	git checkout -

.PHONY: run/%/git-rebase-drift
run/%/git-rebase-drift: ## Rebases a drift branch for the directory '%'
run/%/git-rebase-drift: run/%/git-checkout-drift
	set -e
	DRIFT_BRANCH_NAME=$(GIT_MAIN)-$$(basename $*)-drift
	git reset --hard $(GIT_ORIGIN)/$$DRIFT_BRANCH_NAME
	git fetch $(GIT_ORIGIN)
	echo "Resetting hard to $(GIT_MAIN)"
	git reset --hard $(GIT_ORIGIN)/$(GIT_MAIN)
	git checkout -

.PHONY: run/%/deploy-cm
run/%/deploy-cm: ## Deploy configmap from directory '%'
run/%/deploy-cm: run/%/check
	kubectl create cm $$(basename $*) --from-file $* -oyaml --dry-run=client | kubectl apply -f -

.PHONY: run/%/check
run/%/check: ## Ensure a bunde exists in the directory '%'
	@if [ ! -f $*/bundle.yaml ]; then echo "Bundle does not exist in $*"; exit 1; fi

.PHONY: git-diff
git-diff: ## Run git diff for the whole repository
	git --no-pager diff --exit-code

.PHONY: git-reset
git-reset: ## Run git reset --hard for the whole repository
	git reset $(GIT_ORIGIN)/$$(git branch --show-current) --hard

.PHONY: git-reset-main
git-reset-main: ## Checkout latest main and run git reset --hard
	git fetch $(GIT_ORIGIN)
	git checkout $(GIT_MAIN)
	git reset $(GIT_ORIGIN)/$$(git branch --show-current) --hard

.PHONY: git-push
git-push: ## Pushes the current branch to $(GIT_ORIGIN)
	set -e
	behind_ahead=($$(git rev-list --left-right --count @{u}...HEAD 2>/dev/null))
	behind=$${behind_ahead[0]}
	ahead=$${behind_ahead[1]}
	if [[ $$ahead -gt 0 && $$behind -gt 0 ]]; then \
		echo "Diverged! A force push (--force) may be needed."; \
		if [ "$$(git branch --show-current)" != "$(GIT_MAIN)" ]; then \
			git push --force $(GIT_ORIGIN) $$(git branch --show-current); \
		else \
			echo "Should not push force on $(GIT_MAIN). Exiting with error..."; \
			exit 1; \
		fi; \
	elif [[ $$ahead -gt 0 ]]; then \
		echo "Ahead by $$ahead commits. Pushing..."; \
		git push $(GIT_ORIGIN) $$(git branch --show-current); \
	else \
		echo "Up to date. No need to push anything..."; \
	fi

.PHONY: find
find: ## List all bundle dirs according to bundle pattern var 'BP'
find: guard-BP
	@for f in $$(git ls-files -- "**/bundle.yaml"); do d=$$(dirname $$f); D=$$(basename $$d); if grep -qE "$$BP" <<< "$$D"; then echo "$$d"; fi; done

.PHONY: all/%
all/%: ## Expect BP, then run 'make run/<bundles-found>/%' for each bundle found (e.g. make all/update-bundle BP='.*')
all/%: guard-BP
	for MY_BUNDLE in $$($(MAKE) -f $(MKFILE_FILE) find); do $(MAKE) -f $(MKFILE_FILE) run/$$MY_BUNDLE/$*; done

.PHONY: auto/%
auto/%: ## Expect MY_BUNDLE and then run 'make run/$MY_BUNDLE/%' (e.g. MY_BUNDLE=bundles/oc-bundles/oc-bundle make auto/config)
auto/%: guard-MY_BUNDLE
	$(MAKE) -f $(MKFILE_FILE) run/$(MY_BUNDLE)/$*

.PHONY: help
help: ## Makefile Help Page
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[\/\%a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST) 2>/dev/null

.PHONY: guard-%
guard-%:
	@if [[ "${${*}}" == "" ]]; then echo "Environment variable $* not set"; exit 1; fi
