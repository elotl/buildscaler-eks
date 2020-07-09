# Overview

Buildscaler is a Kubernetes controller that will autoscale a fleet of Buildkite agent pods on your kubernetes cluster.  The agent pods will scale up to run waiting builds and gracefully scale down when agents are idle.

## Architecture

Build pipelines have unique requirements based on the needs of each build.  Some builds require lots of compute resources while others require specialized volumes to be mounted into the build pod.  To allow users to customize the pods that are launched to run a buildkite build, buildscaler requires the user to create a Kubernetes Job that specifies the pod template that will be used to run a Buildkite build job.  Buildscaler will use the Kubernets Job's pod template to launch build pods to run waiting buildscaler builds.

Built-in Kubernetes controllers cannot be used to control the number of running build pod replicas. Blindly using a replica count to scale the number of workers can cause builds to be terminated while still running a job.  Instead, Buildscaler creates and manages pods itself.  This allows it to scale up the number of pods needed to run waiting builds and then gracefully scale down the number of pods when there are excess pods that are not running builds.  Buildscaler does this by asking the Buildkite agent running the pod to gracefully terminate when it is idle.

The combination of allowing a user to specify their build pipeline agent needs as a native Kubernetes resource and gracefully scaling the number of running agents based on waiting builds makes Buildscaler a great fit for running Buildkite builds on Kubernetes.

![Buildscaler Workflow](buildscaler_workflow.png)

# Installation

## Command line instructions

Follow these instructions to install Buildscaler from the command line.

### Prerequisites

* A EKS cluster
* make
* kubectl

### Install from the command line

Set environment variables (modify as necessary):

    export NAME=buildscaler
    export NAMESPACE=default
    export REGISTRY=gcr.io/elotl-public/buildscaler
    export TAG=1.0.0
    export BUILDKITE_ORG_SLUG=my-organization-slug # REQUIRED: change this to your org-slug
    export BUILDKITE_ACCESS_TOKEN_ENCODED= # REQUIRED: fill in with a base64 encoded buildkite access token

Create the namespace in your kubernetes cluster

    kubectl create namespace "$NAMESPACE"

Use make to install the application

    make app/install

## Uninstall

To remove buildscaler, simply:

    $ make app/uninstall

# Backups

Buildscaler is stateless.  It is assumed that the buildscaler job templates are stored in source control and can be easily recreated as necessary.

# Running Buildscaler

## Options
```
Options:
  --token TEXT                    Buildkite API access token. Can be specified
                                  as an environment variable
                                  BUILDKITE_ACCESS_TOKEN  [required]

  --buildkite-org TEXT            The buildkite organization slug the controller
                                  will look for jobs in  [required]

  -n, --namespace TEXT            namespace to look for jobs in, leave blank
                                  for all namespaces. Buildscaler must run with
				  a service account that has access to the
				  namespace

  --sync-interval INTEGER         Number of seconds to wait between syncing
                                  jobs

  --disconnect-after-idle-timeout INTEGER
                                  The number of idle seconds to wait before an
                                  agent is shut down. Used to scale down idle
                                  agents and pods

  --kubeconfig TEXT               Path to the kubeconfig file, if unspecified,
                                  will use InClusterConfig. Can also be
                                  specified with the environment variable:
                                  KUBECONFIG

  -v, --verbose                   More logging output
  --help                          Show this message and exit.
```

## Configuring a Buildscaler Build

In Buildkite, create a build pipeline with one or more build steps.  Configure each build step to run on a single queue (e.g. `queue=my_buildkite_queue`). _Note: each build step can use a different queue but there must be a buildscaler job configured to run builds for each queue._

Create a Kubernetes Job resource with a pod template that is capable of running a Buildkite build step.  The job resource must have the following properties:

- A pod template specifying a container image with everything needed to run the build step including an image, environment variables, secrets for pulling from a private repo, a secret containing the Buildkite agent token, etc..  Baking the Buildkite agent into an image is preferred to downloading the agent for each pod but both workflows are supported.
- The job’s `spec.parallelism` must equal `0`. This prevents the Kubernetes JobController from attempting to run the job itself.
- A label on the job identifying the job as a job managed by buildscaler
- A label on the job specifying a buildkite job queue.
- A Kubernetes Secret containing the Buildkite agent token. This secret is created when deploying buildscaler in the GCE Marketplace.  Note that the Buildscaler system creates 2 different Buildkite secrets with different purposes.  The access token secret is used by buildscaler to query the Buildkite API to determine if there are waiting builds.  The Buildkite agent token is gives build pods the credentials needed to run a buildkite agent.  The buildkite agent token must be included in the job’s pod template in order to run the Buildkite agent inside pods:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  labels:
    app.elotl.co: buildscaler
    buildscaler.elotl.co/queue: my_buildkite_queue
spec:
  parallelism: 0
  template:
    spec:
      containers:
      - name: agent
        # <rest of pod spec has been removed>
        envFrom:
        - secretRef:
            name: buildkite-agent-token
---
apiVersion: v1
kind: Secret
metadata:
  name: buildkite-agent-token
type: Opaque
data:
  BUILDKITE_AGENT_TOKEN: {{ buildkite_agent_token }}
```

### Full example buildscaler job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: bash-job
  labels:
    # both these labels are required. The first identifies this as a
    # buildscaler build, the second says what queue to listen for jobs on
    app.elotl.co: buildscaler
    buildscaler.elotl.co/queue: bash
spec:
  # parallelism must be set to 0, this keeps the standard job controller
  # from running the job
  parallelism: 0
  template:
    spec:
      containers:
      - name: agent
        # the image could be any image with the Buildkite agent installed
          or the agent can be installed via an initContainer
        image: buildkite/agent:3
        envFrom:
        - secretRef:
            name: buildkite-agent-token
        env:
        - name: BASH_JOB
          value: my_bash_job
```

Jobs can be changed and updated while buildscaler is running.  Typically a job will be updated in order to change the job’s pod template to include new environment variables, new image tags or anything else to make the build run correctly.  Since Kubernetes Job pod templates are immutable, the job must be deleted and recreated in order to be updated.  When a job is deleted and then recreated, previously created buildscaler pods associated with the job will be gracefully terminated by telling the Buildkite agent on the pod to shut down when it becomes idle.

## Details

* Buildscaler jobs are linked to buildscaler pods via the queue they listen to.  If 2 pods and agents are listening to the same queue, it is assumed that they were created by the same job. This puts some limitations on jobs.
* Two buildscaler jobs cannot share the same queue.
* A buildscaler job cannot listen to multiple queues.
* The Kubernetes job resource UID is used to identify buildscaler pods created with an out of date template.  Out of date pods are gracefully shut down.
* Pods created by buildscaler will have `restartPolicy: Never`. Buildscaler will manage creating pods whenever necessary.
* If a buildscaler pod has an associated agent but does not have an associated job (a buildscaler job associated with the pod’s buildkite queue) then the pod will be gracefully terminated.
* Any buildscaler pod configured with a queue that does not have both an associated buildscaler job and a running buildscaler agent associated with the pod will be deleted.
* If a pod does not have an associated running agent and the pod was created over 10 minutes ago, the pod will be deleted.  This allows the agent time to start out and times out pods with failed agents.
