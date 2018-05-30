# OpenShift demos

## OpenShift End-to-End Jenkins Pipeline demo with JBoss EAP and PostfreSQL

Simple web application demo.

### Running demo

1. Prepare environment. Cluster administrator creates empty projects, assigns quotes and limits to each one.
It must exist users: devops1, dev1, test1 (or substitute them via env variables, see e2e-pipeline-demo.sh)

```
$ # oc login <as user with cluster-admin role>
$ cd e2e-pipeline-demo
$ export LOGIN_TOKEN=$(oc whoami -t)
$ export OPENSHIFT_MASTER_URL=$(oc whoami --show-server)
$ sh 010-prepare-environment.sh $OPENSHIFT_MASTER_URL
```

2. DevOps User (owner of pipeline) creates applications and other OpenShift objects

```
$ # oc login <as devops1 role>
$ export LOGIN_TOKEN=$(oc whoami -t)
$ sh 110-configure-envinroments.sh $OPENSHIFT_MASTER_URL
```
