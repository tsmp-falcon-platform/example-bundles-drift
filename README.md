# Example Bundles Drift

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Create the bundles repositories](#create-the-bundles-repositories)
  - [Update the repository references](#update-the-repository-references)
- [A note on shared file system](#a-note-on-shared-file-system)
  - [Run without a shared file system](#run-without-a-shared-file-system)
  - [Use existing a shared file system](#use-existing-a-shared-file-system)
  - [Install a Local NFS in your cluster](#install-a-local-nfs-in-your-cluster)
- [Setup for controllers](#setup-for-controllers)
  - [Create the necessary secrets](#create-the-necessary-secrets)
  - [Load the bundles](#load-the-bundles)
    - [Predefined Utility Bundles](#predefined-utility-bundles)
  - [Onboarding](#onboarding)
    - [Create a controller](#create-a-controller)
    - [Bootstrap the controller](#bootstrap-the-controller)
    - [Ensure drift detection](#ensure-drift-detection)
    - [Track changes](#track-changes)
  - [Auditing](#auditing)
  - [Manage Upgrades](#manage-upgrades)
    - [Activate `noop` mode](#activate-noop-mode)
    - [Upgrade the controller](#upgrade-the-controller)
    - [Post-upgrade drift](#post-upgrade-drift)
    - [Deactivate `noop` mode](#deactivate-noop-mode)
  - [Profiles and Transformations](#profiles-and-transformations)
    - [Changing Profiles](#changing-profiles)
  - [Experiment](#experiment)
- [Setup for operation center](#setup-for-operation-center)
  - [Create a static agent](#create-a-static-agent)
  - [Create a cloud and pod template](#create-a-cloud-and-pod-template)
- [Makefile](#makefile)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Create the bundles repositories

This is a template repository to be used as an example for the [bundleutils](https://github.com/tsmp-falcon-platform/ci-bundle-utils) tool.

There is a sibling repository [example-bundles-drift-audit](https://github.com/tsmp-falcon-platform/example-bundles-drift-audit) for the audit bundles.

- create your own repositories from the templates - see [Creating a repository from a template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)
  - one for this repository
  - one for the audit repository

### Update the repository references

We need to replace all occurences of:

- `[B]UNDLEUTILS_BUNDLES_REPO` - with the URL to your version of this repository
- `[B]UNDLEUTILS_AUDIT_REPO` - with the URL to your version of the audit repository

Set new values:

```sh
NEW_BUNDLES_REPO="https://github.com/my-org/my-bundles"
NEW_AUDIT_REPO="https://github.com/my-org/my-bundles-audit"
```

Replace in repository:

```sh
grep -rl "[B]UNDLEUTILS_BUNDLES_REPO" | xargs sed -i "s#[B]UNDLEUTILS_BUNDLES_REPO#${NEW_BUNDLES_REPO}#g"
grep -rl "[B]UNDLEUTILS_AUDIT_REPO" | xargs sed -i "s#[B]UNDLEUTILS_AUDIT_REPO#${NEW_AUDIT_REPO}#g"
```

Commit changes such as:

```sh
❯ git --no-pager diff --minimal
diff --git a/README.md b/README.md
index b2cb0a7..20fb173 100644
--- a/bundles/controller-bundles/bootstrap/items.yaml
+++ b/bundles/controller-bundles/bootstrap/items.yaml
@@ -16,7 +16,7 @@ items:
           userRemoteConfigs:
           - userRemoteConfig:
               credentialsId: github-token-rw
-              url: BUNDLEUTILS_BUNDLES_REPO
+              url: https://github.com/my-org/my-bundles
           branches:
           - branchSpec:
               name: refs/heads/main
```

## A note on shared file system

The jobs below require downloading the docker image of CI for testing.

Downloading the image on every run is inefficient. For this reason, the pod tempalate specifies a `persistentVolumeClaim`:

### Run without a shared file system

If you do not wish to use a shared cache, simply remove the section in the [pod.yaml](./job-scripts/pod.yaml)

Volume mount:

```yaml
    - name: bundleutils-cache
      mountPath: /opt/bundleutils/.cache
```

Volume:

```yaml
  - name: bundleutils-cache
    persistentVolumeClaim:
        claimName: bundleutils-cache-pvc
```

### Use existing a shared file system

If you have a shared file-system, change the values in the [pod.yaml](./job-scripts/pod.yaml) accordingly.

### Install a Local NFS in your cluster

For testing purposes, you can install a local NFS server.

> [!NOTE]
> Adjust namespace, storageClassName, etc accordingly.

Here is an example using EKS:

```sh
NS=cloudbees-core
SCN=gp2
```

Deploy the helm chart:

```sh
helm upgrade --install nfs-server-provisioner \
  nfs-ganesha-server-and-external-provisioner/nfs-server-provisioner \
  --namespace "$NS" \
  --set persistence.enabled=true \
  --set persistence.size=15Gi \
  --set persistence.storageClassName="$SCN" \
  --set storageClass.create=false \
  --set storageClass.defaultClass=false
```

Then deploy the following to create the storage class and persistent volume claim:

```sh
cat <<EOF | kubectl apply --namespace "$NS" -f -
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: internal-nfs
provisioner: cluster.local/nfs-server-provisioner
mountOptions:
  - vers=4.1
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bundleutils-cache-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: internal-nfs
EOF
```

## Setup for controllers

The next steps will guide you through the setup process for controllers.

The setup for the operation center is slightly different and will be covered later.

### Create the necessary secrets

Create the following secrets on the operation center (not a necessity but easier to start with).

The pipeline scripts and checkout require the following credentials:

- `casc-validation-key`  - a single-user wildcard license for the test-server started for validation purposes
- `casc-validation-cert` - a single-user wildcard license for the test-server started for validation purposes
- `github-token-rw`      - for checkout and git pushes
- `bundleutils-creds`    - username and token of jenkins user to export the raw bundle files from the controller

Usage example from the jenkins file:

```groovy
            environment {
                CASC_VALIDATION_LICENSE_KEY = credentials('casc-validation-key')
                CASC_VALIDATION_LICENSE_CERT = credentials('casc-validation-cert')
                GIT_COMMITTER_NAME = 'bundleutils-bot'
                GIT_COMMITTER_EMAIL = 'bundleutils-bot@example.org'
                GIT_AUTHOR_NAME = 'bundleutils-bot'
                GIT_AUTHOR_EMAIL = 'bundleutils-bot@example.org'
            }
            steps {
                withCredentials([
                    gitUsernamePassword(credentialsId: 'github-token-rw', gitToolName: 'Default'),
                    usernamePassword(credentialsId: 'bundleutils-creds', passwordVariable: 'BUNDLEUTILS_PASSWORD', usernameVariable: 'BUNDLEUTILS_USERNAME')]) {
                    dir('bundles') {
                        sh './job-scripts/casc-local-sync.sh'
                    }
                }
            }
```

### Load the bundles

Follow the instructions in the article  [Configure an SCM as the Configuration as Code bundle location](https://docs.cloudbees.com/docs/cloudbees-ci/latest/casc-controller/add-bundle#scm-casc-bundle-location) to add the this repository as a bundle location. Discover the main branch only. We do not need any others.

Example CasC snippet if already using a CasC bundle for the operation center:

```yaml
unclassified:
  bundleStorageService:
    activated: true
    bundles:
    - name: casc-bundles
      retriever:
        SCM:
          ghChecksActivated: false
          scmSource:
            git:
              credentialsId: github-token-rw
              id: 10c9e5df-7d93-455a-98f0-5bf8be353afe
              remote: BUNDLEUTILS_BUNDLES_REPO
              traits:
              - gitBranchDiscovery
              - headRegexFilter:
                  regex: (main)
    checkOutTimeout: 600
    pollingPeriod: 120
    purgeOnDeactivation: false
```

#### Predefined Utility Bundles

There are two pre-defined utility bundles.

- `bootstrap` - This bundle will ensure:
  - the correct plugins are installed
  - create the necessary management jobs
- `noop` - A "no operation" bundle:
  - contains an empty configuration
  - effectively disabling CasC for the controller

### Onboarding

The following steps explain the onboarding process.

> [!TIP]
> If you wish to perform [a managed upgrade](#manage-upgrades) as well, choose a less than latest CI version in the following steps.

#### Create a controller

Create a new controller using the newly loaded `bootstrap` bundle.

The jobs include:

- `casc-local-audit` - Will export the bundle, obfuscate any credentials, and commit any changes to the audit repo.
- `casc-local-bootstrap` - Will bootstrap the current controller to the `bundle-profiles.yaml`.
- `casc-local-direct` - Will sync the sanitized bundle directly to the main branch of the bundles repo.
- `casc-local-drift` - Same as `casc-local-direct` but will sync to a drift branch for review and merge.
- `casc-local-update` - Same as `casc-local-bootstrap` but will update version and/or bundle profile in the `bundle-profiles.yaml`

#### Bootstrap the controller

- Navigate to the new controller
  - Run the `casc-local-bootstrap` job
  - Review the drift branch
  - Create the PR and merge
- Navigate to the operation center
  - load the bundles so that you have the new bundle
  - switch the bundle on the controller item from `bootstrap` to its own `<CONTROLLER>` bundle
- Navigate to the new controller
  - Check for a bundle update
  - Load the new bundle

You have now onboarded your new controller.

#### Ensure drift detection

Your controller is now being managed by the latest version of its own  bundle.

- Navigate to the new controller
  - Run the `casc-local-drift` job
  - The drift branch should exist but without changes

Drift detection has not detected any drift from the main branch.

#### Track changes

Let's make a change and try again.

- Navigate to the new controller
  - Make a change to the system message.
  - Run the `casc-local-drift` job
  - The drift branch should exist and include the changes made above
  - Review the drift branch changes
  - **Are the changes expected?**
    - Create the PR and merge
  - **Are the changes unwanted?**
    - Force reload the bundle and revert them

### Auditing

The `casc-local-audit` job will create a comprehensive but non-viable version of the bundle. This is saved in the audit repository.

- Navigate to the new controller
  - Run the `casc-local-audit` job
  - Make a change to the system message
  - Run the `casc-local-audit` job again
  - Examine the commits in the audit repository
  - Run the `casc-local-audit` job again
  - Notice that no commit is performed if no changes are detected

The audit job:

- can be triggered any time
- is extremely fast since it does not perform validation

### Manage Upgrades

The following explains **one way (there are others)** to manage controller upgrades.

- If not already done, create a controller with a less than latest CI version.
  - Follow the [onboarding process](#onboarding) above.

#### Activate `noop` mode

Since CasC in one version may be incompatible with another, let's disable CasC for the upgrade.

- Navigate to the operation center
  - switch the bundle on the controller item to use the `noop` bundle

#### Upgrade the controller

Upgrade the controller as you would normally do.

- Navigate to the operation center
  - switch the image on the controller item
  - notice the 'stale' notification
  - reprovision the controller

> [!TIP]
> If you are managing the OC bundle in the same way, now would be the time to review and sync the controller item changes to the OC bundle.

#### Post-upgrade drift

Now the controller has been updated, let's check if there were any changes to the CasC configuration.

First, we'll need to update the `bundle-profiles.yaml` entry to include the new controller version.

- Navigate to the controller
  - Run the `casc-local-update` job
    - The entry is updated and validation performed on the new bundle
    - This is effectively the same as running `casc-local-drift`
  - Review the drift branch changes
  - **Are the changes expected?**
    - Create the PR and merge
  - **Are the changes unwanted?**
    - Investigate and decide upon a course of action

Assuming the changes are verified and merged...

- Navigate to the controller
  - Run the `casc-local-drift` job
  - There should be no changes detected

#### Deactivate `noop` mode

Assuming we have merged any post-upgrade changes, we want to start managing the controller again.

- Navigate to the operation center
  - switch the bundle on the controller item from the `noop` to use the `<CONTROLLER>` bundle
- Navigate to the operation center
  - load the bundles so that you have the new bundle
  - switch the bundle on the controller item from `bootstrap` to its own `<CONTROLLER>` bundle
- Navigate to the new controller
  - Check for a bundle update
  - Load the new bundle

You have successfully navigated through an upgrade.

### Profiles and Transformations

The [bundle-profiles.yaml](./bundle-profiles.yaml) introduces the concept of profiles for bundles.

- A profile provides preconfigured values for the bundleutils tool.
- A profile also specifies which transformations the bundle should undertake.

Information [explaining transformations](https://github.com/tsmp-falcon-platform/ci-bundle-utils/blob/main/docs/explaining-transformations.md#explaining-transformations) can be found on the tools docs.

Let us consider two of the profiles in [bundle-profiles.yaml](./bundle-profiles.yaml). They differ in the transformations used:

- [controllers-common.yaml](./transformations/controllers-common.yaml)     - a starter profile which removes a lot of config (effectively meaning if is not managed or tracked)
- [controllers-advanced.yaml](./transformations/controllers-advanced.yaml) - a more detailed approach, managing the jobs and splitting configuration into separate files

#### Changing Profiles

Consider your current bundle produced using the `controllers-common` profile.

It will look something like this:

```sh
❯ ls -1 bundles/controller-bundles/CONTROLLER
bundle.yaml
jenkins.yaml
plugins.yaml
```

Let us change the profile.

- Navigate to the controller
  - Run the `casc-local-update` job
    - This time changing the profile parameter to `controllers-advanced`
    - The entry is updated and validation performed on the new bundle
    - This is effectively the same as running `casc-local-drift`
  - Review the drift branch changes
  - **Are the changes expected?**
    - Create the PR and merge
  - **Are the changes unwanted?**
    - Re-run the `casc-local-update` leaving the profile as `controller-common`

If merged, the new bundle structure will look something like:

```sh
❯ ls -1 bundles/controller-bundles/CONTROLLER
bundle.yaml
items.yaml
jenkins.casc.yaml
jenkins.credentials.yaml
jenkins.jenkins.clouds.yaml
jenkins.security.yaml
jenkins.support.yaml
jenkins.views.yaml
jenkins.yaml
plugins.yaml
```

### Experiment

Experiment with making your own changes to the [controllers-advanced.yaml](./transformations/controllers-advanced.yaml) or creating new transformations and profiles.

## Setup for operation center

The main difference between operation center and a controller is:

- the lack of an agent to run the jobs
  - controllers use a kubernetes cloud and a pipeline job with a pod template
- the lack of a pipeline job and jenkinsfile
  - we can use freestyle only

There are various solutions and it is not scope to say which is best for your situation. However, the end result should be:

- we have an agent with a specific label
- we have freestyle jobs which can run the same steps as found in the `bootstrap` bundle.

### Create a static agent

This option would entail running a static agent. Options here include:

- creating a StatefulSet using the ci-bundle-utils docker image, or running a static pod
- creating a static agent in the OC
- calling the `java -jar ...` etc?

Difficult to manage in my opinion.

### Create a cloud and pod template

A more dynamic approach is to create a cloud and pod template in the operation center.

More information on this can be found at [Running Remotely on the Operations Center](https://github.com/tsmp-falcon-platform/ci-bundle-utils/blob/main/docs/setup-cloudbees-casc.md#running-remotely-on-the-operations-center) in the tool repo.

## Makefile

A [Makefile](./Makefile) has been provided with some common tasks.

<!-- START makefile-doc -->
```bash
$ make help


Usage:
  make <target>

Targets:
  bootstrap                  Run bundleutils bootstrap according to the JENKINS_URL
  run/%/config               Run bundleutils config in the directory '%'
  run/%/update-bundle        Run bundleutils update-bundle in the directory '%'
  run/%/audit                Run bundleutils audit in the directory '%'
  run/%/fetch                Run bundleutils fetch in the directory '%'
  run/%/transform            Run bundleutils fetch in the directory '%'
  run/%/refresh              Run bundleutils fetch and transform in the directory '%'
  run/%/ci-start             Setup and start test-server according to the directory '%'
  run/%/ci-validate          Run ci-validation for the directory '%'
  run/%/ci-stop              start test-server according to in the directory '%'
  run/%/validate             Run validation steps in the directory '%'
  run/%/all                  Run all steps in the directory '%'
  run/%/git-diff             Run git diff in the directory '%'
  run/%/git-commit           Run git commit in the directory '%'
  run/%/git-handle-drift     Creates or rebases drift branch for the directory '%'
  run/%/git-checkout-drift   Checks out a drift branch for the directory '%'
  run/%/git-create-drift     Creates a drift branch for the directory '%'
  run/%/git-rebase-drift     Rebases a drift branch for the directory '%'
  run/%/deploy-cm            Deploy configmap from directory '%'
  run/%/check                Ensure a bunde exists in the directory '%'
  git-diff                   Run git diff for the whole repository
  git-reset                  Run git reset --hard for the whole repository
  git-reset-main             Checkout latest main and run git reset --hard
  git-push                   Pushes the current branch to $(GIT_ORIGIN)
  find                       List all bundle dirs according to bundle pattern var 'BP'
  all/%                      Expect BP, then run 'make run/<bundles-found>/%' for each bundle found (e.g. make all/update-bundle BP='.*')
  auto/%                     Expect MY_BUNDLE and then run 'make run/$MY_BUNDLE/%' (e.g. MY_BUNDLE=bundles/oc-bundles/oc-bundle make auto/config)
  help                       Makefile Help Page
```
<!-- END makefile-doc -->