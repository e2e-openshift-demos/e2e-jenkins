#!/bin/bash

dir1=$(realpath $E `dirname $BASH_SOURCE`)
. $dir1/$(basename $dir1).sh || { echo "Couldn't load '$dir1/$(basename $dir1).sh'" ; exit 1 ; } 

clear

show_env '.*_ENVS\?' '.*_USER'
pause

oc_login $1

oc_get_resources template -n openshift $APP_TEMPLATE_NAME || \
    oc_create_resource_as_admin_from templates/${APP_TEMPLATE_NAME}.json -n openshift

oc_get_resources is -n openshift $APP_RUNTIME_IMAGESTREAM_NAME || \
    oc_create_resource_as_admin_from templates/${APP_RUNTIME_IMAGESTREAM_NAME}.json -n openshift

oc_get_resources template -n openshift $DB_TEMPLATE_NAME || \
    oc_create_resource_as_admin_from templates/${DB_TEMPLATE_NAME}.json -n openshift

oc_get_resources is -n openshift $DB_RUNTIME_IMAGESTREAM_NAME || \
    die "Install OpenShift Common ImageStreams, see templates/README.md"

show_comment "Create projects: $CICD_ENV $ALL_ENVS"
for p in $CICD_ENV $ALL_ENVS ; do
    oc_project_as_admin ${PROJECT_NAME_PREFIX}-$p --admin $CICD_USER
    oc_create_resource_as_admin quota -n ${PROJECT_NAME_PREFIX}-$p compute --scopes=NotTerminating --hard=cpu=4,memory=4G
    oc_create_resource_as_admin quota -n ${PROJECT_NAME_PREFIX}-$p logical --hard=pods=10,services=5,secrets=20,persistentvolumeclaims=2
    oc_create_resource_as_admin quota -n ${PROJECT_NAME_PREFIX}-$p timelimited --scopes=Terminating --hard=cpu=4,memory=4G,pods=4
    oc_create_resource_as_admin_from limit-ranges.yaml -n ${PROJECT_NAME_PREFIX}-$p
done

oc_logout
