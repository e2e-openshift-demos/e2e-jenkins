#!/bin/bash

dir1=$(realpath $E `dirname $BASH_SOURCE`)
. $dir1/$(basename $dir1).sh || { echo "Couldn't load '$dir1/$(basename $dir1).sh'" ; exit 1 ; } 

clear

APP_NAME=app
SOURCE_REPOSITORY_URL=https://github.com/dsevost/eap-6-pg-test
SOURCE_REPOSITORY_REF=master
SRC_DIR=/
DATASOURCE_NAME=AppJDBC
SQL_INIT_QUERY="
create table if not exists keypair (k integer not null primary key, v varchar(256));
insert into keypair VALUES (1, 'value 1');
insert into keypair VALUES (2, 'value 2');
select k,v from keypair;
"

export MAVEN_MIRROR_URL=http://static-content.apps.dsevosty.info/maven/repo
#MAVEN_MIRROR_URL=""

EAP_SERVICE_ACCOUNT=${APP_NAME}-eap-sa
EAP_SECRET=${APP_NAME}-eap-secret

DOMAIN=${DOMAIN:-${DEMO_APPS_DOMAIN}.${OSE30_DOMAIN_NAME}}

show_env '.*_ENVS\?' '.*_USER' '^DOMAIN' '.*_MIRROR'
pause

if false ; then

oc_login $1

command -v keytool > /dev/null || die "Java keytool utility not found, please install JRE 1.8 or later"

rm -vf tmp/*.jks tmp/*.jceks

show_comment "Set Edit permission to 'jenkins' SystemAccount for projects: $ALL_ENVS"
for p in $ALL_ENVS ; do
    oc_policy add-role-to-user edit system:serviceaccount:${PROJECT_NAME_PREFIX}-${CICD_ENV}:jenkins -n ${PROJECT_NAME_PREFIX}-$p
done

show_comment "Set Edit permission to Developer user for projects: $DEV_ENVS"
for p in $DEV_ENVS ; do
    oc_policy add-role-to-user edit $DEV_USER -n ${PROJECT_NAME_PREFIX}-$p
done

show_comment "Set Edit permission to Tester user for projects: $TEST_ENVS"
for p in $TEST_ENVS ; do
    oc_policy add-role-to-user edit $TEST_USER -n ${PROJECT_NAME_PREFIX}-$p
done

oc_create_resource_from templates/jenkins-simple-dev_test_prod-template.yaml -n ${PROJECT_NAME_PREFIX}-${CICD_ENV}

oc_new_app_from_template simple-dev-test-prod-pipeline -n ${PROJECT_NAME_PREFIX}-${CICD_ENV} \
    -p APP_NAME=$APP_NAME

oc_exec_local set resources dc/jenkins --requests=cpu=800m,memory=500Mi --limits=cpu=1000m,memory=1000Mi -n ${PROJECT_NAME_PREFIX}-${CICD_ENV}
#fi

for p in $DEV_ENVS $TEST_ENVS; do

    cmd="\
	keytool -genkeypair -alias jboss -keyalg RSA \
	-keystore tmp/server-${p}.keystore.jks \
	-storepass mykeystorepass \
	-storetype PKCS12 \
	-v \
	--dname \
	    'CN=https-secret,OU=SolutionArchitect,O=RedHat,L=Moscow,C=RU' \
    "
    show_comment "Generating Java keystore for JBoss EAP instance" "$cmd"
    eval $cmd
    pause

    cmd="\
	keytool -genseckey -alias jgroups \
	-keystore tmp/jgroups-${p}.jceks \
	-keypass jgroupstorepass \
	-storepass jgroupstorepass \
	-storetype JCEKS
	-v \
	--dname \
	    'CN=jgroup-secret,OU=SolutionArchitect,O=RedHat,L=Moscow,C=RU' \
    "
    show_comment "Generating Java keystore for JBoss EAP instance" "$cmd"
    eval $cmd
    pause

    oc_exec_local delete secret ${EAP_SECRET} -n ${PROJECT_NAME_PREFIX}-$p
    oc_exec_local delete sa $EAP_SERVICE_ACCOUNT -n ${PROJECT_NAME_PREFIX}-$p
    oc_create_resource secret generic ${EAP_SECRET} \
	--from-file=keystore.jks=tmp/server-${p}.keystore.jks,jgroups.jceks=tmp/jgroups-${p}.jceks \
	-n ${PROJECT_NAME_PREFIX}-$p
    oc_create_resource sa $EAP_SERVICE_ACCOUNT -n ${PROJECT_NAME_PREFIX}-$p
    cmd="oc secret link $EAP_SERVICE_ACCOUNT ${EAP_SECRET} -n ${PROJECT_NAME_PREFIX}-$p"
    show_comment "Linking secret with ServiceAccount" "$cmd"
    oc_exec_local $cmd

    oc_new_app_from_template $APP_TEMPLATE_NAME -n ${PROJECT_NAME_PREFIX}-$p \
	-p APPLICATION_NAME=$APP_NAME \
	-p SOURCE_REPOSITORY_URL=$SOURCE_REPOSITORY_URL \
	-p SOURCE_REPOSITORY_REF=dev \
	-p CONTEXT_DIR=$SRC_DIR \
	-p DB_JNDI=java:jboss/datasources/$DATASOURCE_NAME \
	-p MAVEN_MIRROR_URL=$MAVEN_MIRROR_URL \
	-p HTTPS_SECRET=${EAP_SECRET} \
	-p HTTPS_NAME=jboss \
	-p HTTPS_PASSWORD=mykeystorepass \
	-p HTTPS_KEYSTORE_TYPE=PKCS12 \
	-p JGROUPS_ENCRYPT_SECRET=${EAP_SECRET} \
	-p JGROUPS_ENCRYPT_NAME=jgroups \
	-p JGROUPS_ENCRYPT_PASSWORD=jgroupstorepass \
	-e OPENSHIFT_KUBE_PING_NAMESPACE=${PROJECT_NAME_PREFIX}-$p

    cmd="\
    set deployment-hook dc/${APP_NAME}-postgresql -n ${PROJECT_NAME_PREFIX}-$p \
	--failure-policy=ignore \
	--post \
	    -e SQL_INIT_QUERY=\"\$SQL_INIT_QUERY\" \
	    -- \"/bin/bash -c '
		    echo \\\$SQL_INIT_QUERY | \
		    PGPASSWORD=\\\$POSTGRESQL_PASSWORD psql \
			-h \\\${$(echo ${APP_NAME} | tr [:lower:] [:upper:])_POSTGRESQL_SERVICE_HOST} \
			\\\$POSTGRESQL_DATABASE \
			-U \\\$POSTGRESQL_USER \
		'\"\
    "
    show_comment "Installing database post-deployment hook" "$cmd"
    oc_exec_local "$cmd"
    pause

    oc_exec_local set resources dc/${APP_NAME} --requests=cpu=500m,memory=256Mi --limits=cpu=500m,memory=256Mi -n ${PROJECT_NAME_PREFIX}-${CICD_ENV}
done

#oc_exec_local -n eap-db-test set triggers bc $APP_NAME --from-config --remove

#fi

oc_new_app_from_template postgresql-ephemeral -n ${PROJECT_NAME_PREFIX}-prod \
    -p MEMORY_LIMIT=256Mi \
    -p POSTGRESQL_DATABASE=$APP_NAME \
    -p DATABASE_SERVICE_NAME=${APP_NAME}-postgresql

oc_policy add-role-to-group system:image-puller system:serviceaccount:${PROJECT_NAME_PREFIX}-prod -n ${PROJECT_NAME_PREFIX}-test

fi

oc_new_app_from_imagestream ${PROJECT_NAME_PREFIX}-test/${APP_NAME}:promoteProd $APP_NAME "" \
    -n ${PROJECT_NAME_PREFIX}-prod \
    --allow-missing-imagestream-tags \
    -e DB_SERVICE_PREFIX_MAPPING=${APP_NAME}-postgresql=DB_DATABASE \
    -e DB_DATABASE_JNDI=java:jboss/datasources/$DATASOURCE_NAME \
    -e JGROUPS_CLUSTER_PASSWORD=$(cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c1 -c32) \
    -e JGROUPS_PING_PROTOCOL=openshift.DNS_PING \
    -e OPENSHIFT_KUBE_PING_NAMESPACE=${PROJECT_NAME_PREFIX}-prod \
    -e OPENSHIFT_DNS_PING_SERVICE_PORT=8888 \
    -e OPENSHIFT_DNS_PING_SERVICE_NAME=${APP_NAME}-ping

oc_exec_local label is/$APP_NAME app=$APP_NAME

cmd="-n ${PROJECT_NAME_PREFIX}-prod set env dc/${APP_NAME} --from=secret/${APP_NAME}-postgresql --prefix=DB_"
show_comment "Installing database post-deployment hook" "oc $cmd"
oc_exec_local $cmd
pause

oc_exec_local -n ${PROJECT_NAME_PREFIX}-prod get dc/${APP_NAME} -o yaml | \
    sed 's/DB_DATABASE_USER$/DB_DATABASE_USERNAME/ ; s/DB_DATABASE_NAME/DB_DATABASE_DATABASE/' | \
    oc_exec_local replace -f -

oc_expose_resource dc $APP_NAME -n ${PROJECT_NAME_PREFIX}-prod --port=8888 --name=${APP_NAME}-ping
oc_exec_local label svc/${APP_NAME}-ping app=$APP_NAME --overwrite
oc_exec_local annotate svc/${APP_NAME}-ping \
    "service.alpha.kubernetes.io/tolerate-unready-endpoints=true"
#    "description=The JGroups ping port for clustering."

#oc_expose_resource dc $APP_NAME -n ${PROJECT_NAME_PREFIX}-prod --port=8080
oc_expose_resource svc $APP_NAME -n ${PROJECT_NAME_PREFIX}-prod --hostname=www-${PROJECT_NAME_PREFIX}.$DOMAIN

#fi

oc_expose_resource dc $APP_NAME -n ${PROJECT_NAME_PREFIX}-prod --port=8443 --name=${APP_NAME}-ssl
oc_expose_resource svc ${APP_NAME}-ssl -n ${PROJECT_NAME_PREFIX}-prod --hostname=secure-${PROJECT_NAME_PREFIX}.$DOMAIN
