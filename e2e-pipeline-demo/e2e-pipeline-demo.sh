#!/bin/bash

dir1=$(realpath $E `dirname $BASH_SOURCE`/..)
. $dir1/common.sh || { echo "Couldn't load '$dir1/common.sh'" ; exit 1 ; } 

export PROJECT_NAME_PREFIX=eap-jdbc

export CICD_USER=${CICD_USER:-devops1}
export DEV_USER=${DEV_USER:-dev1}
export TEST_USER=${TEST_USER:-test1}

export DEV_ENVS="dev"
export TEST_ENVS="test"
export BUILD_ENVS="$DEV_ENVS $TEST_ENVS"
export DEPLOY_ENVS="prod"
export CICD_ENV="cicd"

export ALL_ENVS="$BUILD_ENVS $DEPLOY_ENVS"

export APP_TEMPLATE_NAME=eap64-postgresql-s2i
export APP_RUNTIME_IMAGESTREAM_NAME=jboss-eap64-openshift

export APP_TEMPLATE_NAME=eap71-postgresql-s2i
export APP_RUNTIME_IMAGESTREAM_NAME=jboss-eap71-openshift

export DB_TEMPLATE_NAME=postgresql-persistent
export DB_RUNTIME_IMAGESTREAM_NAME=postgresql

SQL_CREATE_TABLE_QUERY="
create table keypair (
 k integer not null,
 v varchar(250),
 primary key (k)
)
"

# oc -n eap-db-dev patch bc/app -p '[{"op": "add", "path": "/spec/source/git/ref", "value": "dev"}]' --type=json
