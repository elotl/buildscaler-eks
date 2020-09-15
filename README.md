# Overview

Buildscaler is a Kubernetes controller that will autoscale a fleet of Buildkite agent pods on your Kubernetes cluster.  The agent pods will scale up to run waiting builds and gracefully scale down when agents are idle.

## Architecture

Build pipelines have unique requirements based on the needs of each build.  Some builds require lots of compute resources while others require specialized volumes to be mounted into the build pod.  To allow users to customize the pods that are launched to run a Buildkite build, Buildscaler requires the user to create a Kubernetes Job that specifies the pod template that will be used to run a Buildkite build job.  Buildscaler will use the Kubernets Job's pod template to launch build pods to run waiting Buildscaler builds.

Built-in Kubernetes controllers cannot be used to control the number of running build pod replicas. Blindly using a replica count to scale the number of workers can cause builds to be terminated while they are still running.  Instead, Buildscaler creates and manages pods itself.  This allows it to scale up the number of pods needed to run waiting builds and then gracefully scale down the number of pods when there are excess pods that are not running builds.  Buildscaler does this by asking the Buildkite agent running the pod to gracefully terminate when it is idle.

The combination of allowing a user to specify their build pipeline agent needs as a native Kubernetes resource and gracefully scaling the number of running agents based on waiting builds makes Buildscaler a great fit for running Buildkite builds on Kubernetes.

![Buildscaler Workflow](buildscaler_workflow.png)

# Installation

## Command line instructions

Follow these instructions to install Buildscaler from the command line.

### Prerequisites

* A EKS cluster, Kubernetes 1.16 or higher configured with [IAM Roles for Service Accounts}(https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
* kubectl

### Create an IAM role for the buildscaler service account

1. Enable OIDC for service accounts in your cluster by following the instructions [here](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html).
2. Create service account linked IAM role for Buildscaler:

Create an IAM role for the Buildscaler pod and configure it with the following policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "aws-marketplace:RegisterUsage",
                "aws-marketplace:MeterUsage"
            ],
            "Resource": "*"
        }
    ]
}
```
Create a trust relationship on the IAM role, with the following fields replaced

* Replace `$AWS_ACCOUNT_ID` with your AWS account ID (e.g. 123456789012)
* Replace `$OIDC_PROVIDER` with your cluster's OIDC provider's URL (e.g. oidc.eks.us-east-1.amazonaws.com/id/AAAABBBBCCCCDDDDEEEEFFFF00001111)
* Replace `$NAMESPACE` with the namespace buildscaler will run in (defaults to the default namespace)
* Replace `$BUILDSCALER_SERVICE_ACCOUNT_NAME` with the name of the buildscaler service account (defaults to "buildscaler")

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$OIDC_PROVIDER"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "$OIDC_PROVIDER:sub": "system:serviceaccount:$NAMESPACE:$BUILDSCALER_SERVICE_ACCOUNT_NAME"
        }
      }
    }
  ]
}
```

### Install from the command line

Set environment variables (be sure to modify BUILDKITE_ORG_SLUG, BUILDKITE_ACCESS_TOKEN and BUILDKITE_AGENT_TOKEN with your organizations values):

    export NAME=buildscaler
    export NAMESPACE=default # change this as necessary. Buildscaler will run pods in this namespace
    export BUILDKITE_ORG_SLUG=my-organization-slug # REQUIRED: change this to your company's Buildkite org-slug
    export BUILDKITE_ACCESS_TOKEN=0123456789abcdef0123456789abcdef0123456789abcdef01 # REQUIRED: fill in with your Buildkite access token
    export BUILDKITE_AGENT_TOKEN=aaaabbbbccccddddeeeeffffaaaabbbbccccddddeeeeffffff # REQUIRED: fill in with your Buildkite agent token
    export BUILDSCALER_SERVICE_ACCOUNT_ROLE_ARN=arn:aws:iam::123456789012:role/buildscaler # REQUIRED: fill in with the ARN of the IAM role for buildscaler
To deploy Buildscaler, use the script:

    ./manifests/deploy.sh

## Uninstall

To remove Buildscaler, delete the Buildscaler deployment then delete any Buildscaler job templates that have been created.

    $ kubectl -n$NAMESPACE delete Deployment,Secret,ServiceAccount,Role,RoleBinding -l app.kubernetes.io/name=$NAME
    $ kubectl -n$NAMESPACE delete jobs,pods -l app.elotl.co=buildscaler

# Running Buildscaler

## Options
```
Options:
  --token TEXT                    Buildkite API access token. Can be specified
                                  as an environment variable
                                  BUILDKITE_ACCESS_TOKEN  [required]

  --buildkite-org TEXT            The Buildkite organization slug the controller
                                  will look for jobs in  [required]

  -n, --namespace TEXT            Namespace to look for jobs in, leave blank
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

In Buildkite, create a build pipeline with one or more build steps.  Configure each build step to run on a single queue (e.g. `queue=my_buildkite_queue`). _Note: each build step can use a different queue but there must be a Buildscaler job configured to run builds for each queue._

Create a Kubernetes Job resource with a pod template that is capable of running a Buildkite build step.  The job resource must have the following properties:

- A pod template specifying a container image with everything needed to run the build step including an image, environment variables, secrets for pulling from a private repo, a secret containing the Buildkite agent token, etc..  Baking the Buildkite agent into an image is preferred to downloading the agent for each pod but both workflows are supported.
- The job’s `spec.parallelism` must equal `0`. This prevents the Kubernetes JobController from attempting to run the job itself.
- A label on the job identifying the job as a job managed by Buildscaler
- A label on the job specifying a Buildkite job queue.
- A Kubernetes Secret containing the Buildkite agent token. This secret is created when deploying Buildscaler.  Note that the Buildscaler system creates 2 different Buildkite secrets, each with a different purpose.  The access token secret is used by Buildscaler to query the Buildkite API to determine if there are waiting builds and query running agents.  The Buildkite agent token is gives build pods the credentials needed to run a buildkite agent and connect to Buildkite.  The Buildkite agent token must be included in the job’s pod template in order to run the Buildkite agent inside pods:

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

Jobs can be changed and updated while Buildscaler is running.  Typically a job will be updated in order to change the job’s pod template to include new environment variables, new image tags or anything else to make the build run correctly.  Since Kubernetes Job pod templates are immutable, the job must be deleted and recreated in order to be updated.  When a job is deleted and then recreated, previously created Buildscaler pods associated with the job will be gracefully terminated by telling the Buildkite agent on the pod to shut down when it becomes idle.

## Details

* Buildscaler jobs are linked to Buildscaler pods via the queue they listen to.  If 2 pods and agents are listening to the same queue, it is assumed that they were created by the same job. This puts some limitations on jobs.
* Two Buildscaler jobs cannot share the same queue.
* A Buildscaler job cannot listen to multiple queues.
* The Kubernetes job resource UID is used to identify Buildscaler pods created with an out of date template.  Out of date pods are gracefully shut down.
* Pods created by Buildscaler will have `restartPolicy: Never`. Buildscaler will manage creating or recreating pods whenever necessary.
* If a Buildscaler pod has an associated agent but does not have an associated job (a Buildscaler job associated with the pod’s Buildkite queue) then the pod will be gracefully terminated.
* Any Buildscaler pod configured with a queue that does not have both an associated Buildscaler job and a running Buildscaler agent associated with the pod will be deleted.
* If a pod does not have an associated running agent and the pod was created over 10 minutes ago, the pod will be deleted.  This allows the agent time to start but adds a timeout to pods with failed agents.
