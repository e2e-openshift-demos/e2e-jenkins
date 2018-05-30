#!/bin/bash

case $(uname -s) in
  Darwin)
    E=
    ;;
  Linux)
    E='-e'
    ;;
esac

#dir1=$(realpath $E `dirname $BASH_SOURCE`/..)
#. $dir1/env.sh || { echo "Couldn't load '$dir1/func.sh'" ; exit 1 ; } 

#load_script ../openshift/openshift.sh

function die() {
    local msg="$1"
    local exit_code=${2:-1}
    echo "$msg"
    exit $exit_code
}

function pause() {
    local x
    echo -e "\n\nHit ENTER to continue..."
    read x
}

function show_comment() {
    clear
    echo -e $1 "\n\n" $2
    pause
}

function oc_check_existence() {
    command -v oc 1>/dev/null 2>&1 && return 0

    local oc_client_archive="https://github.com/openshift/origin/releases/download/v1.3.1/openshift-origin-client-tools-v1.3.1-dad658de7465ba8a234a4fb40b5b446a45a4cee1-linux-64bit.tar.gz"
    local oc_archive="/tmp/oc-clients.tar.gz"

    mkdir -p ~/bin
    curl -L $oc_client_archive -o $oc_archive
    oc_name=$(tar -tzf $oc_archive 2> /dev/null |grep /oc)
    tar -C ~/bin -xzf $oc_archive $oc_name --strip 1
}

function oc_exec_local() {
    oc_check_existence || die "Error while checking Openshift client's tools"
    [ "$1" = "oc" ] && shift
    eval oc "$*"
}

function oadm_remote_policy() {
    CMD="oc adm policy $*"
    show_comment "Manage policy" "$CMD"
    oc_exec_remote $CMD || die "Error while manage policy"
}

function oc_policy() {
    CMD="oc adm policy $*"
    show_comment "Manage policy" "$CMD"
    oc_exec_local $CMD || die "Error while manage policy"
    pause
}

function oc_exec_remote() {
    local cmd=$1
    if [ "$cmd" = "oc" -o "$cmd" = "oadm" ] ; then
	shift
    else
	cmd=oc
    fi
#    if [ -z "$MASTER_NODE" ] ; then
#	ssh_host="${OSE_NAME_PREFIX}${OSE_VER}-master01"
#    else
#	ssh_host=$MASTER_NODE
#    fi
#    ssh -qt root@$ssh_host $cmd "$*"
    exec_remote_command \
	"$*"
}

function oc_create_resource_as_admin() {
    oc_create_resource $* --as=system:admin
}

function oc_create_resource() {
    local resource=$1
    shift
    local args=$*

    CMD="oc create $resource $args"
    show_comment "Creating resource $resource" "$CMD"
    oc_exec_local $CMD || die "Error while creating resource: $resource_url"
    pause
}

function oc_create_resource_as_admin_from() {
    oc_create_resource_from $* --as=system:admin
}
function oc_create_resource_from() {
    local resource_url=$1
    shift

    CMD="oc create -f $resource_url $*"
    show_comment "Creating resource from $resource_url" "$CMD"
    oc_exec_local  $CMD || die "Error while creating resource: $resource_url"
    pause
}

function oc_get_resources() {
    local resources="$*"
    local rc

    CMD="oc get $resources"
    show_comment "Getting $resources" "$CMD"
    oc_exec_local $CMD
    rc=$?
#    || die "Error while listing resources: $resources"
    pause
    return $rc
}

function oc_expose_resource() {
    local resources="$1"
    shift
    local args="$*"

    CMD="oc expose $resources $args"
    show_comment "Exposing $resources" "$CMD"
    oc_exec_local $CMD || die "Error while exposing resources: $resources"
    pause
}

function oc_load_template() {
    local name=$1

    oc get templates $name || oc create -f ${name}.yaml
}

function oc_login() {

    local url=${1:-https://master01.$OSE30_DOMAIN_NAME:8443}
    local credential
    local CMD

    if [ -z "$LOGIN_TOKEN" ] ; then
	if [ -z "$USER" -o -z "$USER_PASSWORD" ] ; then
	    die "Syntax: <LOGIN_TOKEN=openshift_login_token | USER=user USER_PASSWORD=password> $0 [OPENSHIFT_MASTER_URL]"
	else
	    credentials="-u $USER -p $USER_PASSWORD"
	fi
    else
	credentials="--token=$LOGIN_TOKEN"
    fi
    CMD="oc login \
	    $credentials \
	    --insecure-skip-tls-verify=true \
	    --server=$url"

    show_comment "Login to Openshift as $USER" "$CMD"
    oc_exec_local \
	$CMD  \
        || die "Error while login to $url as $credentials "
    pause
}

function oc_logout() {
    local user=$(oc_exec_local whoami)
    local CMD="oc logout"

    show_comment "Logout $user" "$CMD"
    oc_exec_local $CMD \
        || die "Error while login out from $(oc_exec_local whoami --show-server) as $user"
}

function oc_new_app_from_imagestream() {
    local imagestream=$1
    local app_name=$2
    local app_src=$3
    shift 3
    local CMD

    CMD="oc new-app $app_src -i $imagestream --name=$app_name $*"
    show_comment "Creating new application from ImageStream $imagestream for source $APP_SRC" "$CMD"
    oc_exec_local \
	$CMD \
	    || die "Error wile creating new-app"
    pause
}

function oc_new_app_from_template() {
    local template=$1
    shift
    local params=$*
    local CMD

    CMD="oc new-app --template=$template $params"
    show_comment "Creating new application from template $template" "$CMD"
    oc_exec_local \
	$CMD \
	    || die "Error wile creating new-app"
    pause
}

function oc_project() {
    local pname=$1
    local dname
    local desc
    local CMD

    [ -z "$pname" ] && die "You must specify a project name to use or create"
    [ -z "$PROJECT_LONG_NAME" ] || dname="--display-name='$PROJECT_LONG_NAME'"
    [ -z "$PROJECT_DESCRIPTION" ] || desc="--description='$PROJECT_DESCRIPTION'"

    CMD="oc new-project $dname $desc $pname"
    show_comment "Create a new project $pname" "$CMD"
    oc_exec_local \
	$CMD \
	    || die "Error while creating project $pname"
    pause
}

function oc_project_as_admin() {
    local pname=$1
    shift
    local dname
    local desc
    local CMD

    [ -z "$pname" ] && die "You must specify a project name to use or create"
    [ -z "$PROJECT_LONG_NAME" ] || dname="--display-name='$PROJECT_LONG_NAME'"
    [ -z "$PROJECT_DESCRIPTION" ] || desc="--description='$PROJECT_DESCRIPTION'"

    CMD="oc --as=system:admin adm new-project $dname $desc $pname $*"
    show_comment "Create a new project $pname" "$CMD"
    oc_exec_local \
	$CMD \
	    || die "Error while creating project $pname"
    pause
}

function oc_patch() {
    local resource_type=$1
    local resource_name=$2
    shift 2
    local patch_str="$*"

    CMD="oc patch $resource_type $resource_name -p '$patch_str'"
    show_comment "Pathcing resource $resource_name" "$CMD"
    oc_exec_local \
	$CMD \
	    || die "Error while patching resource $resource_name"
    pause
}

function oc_project_remove() {
    local pname=$1
    local CMD

    [ -z "$pname" ] && die "You must specify a project name to remove"
    CMD="oc delete project $1"
    show_comment "Removing project $pname"
    echo \
	$CMD
    pause
}

function oc_remove_resource_for_name() {
    local resource="$1"
    local resource_name=$2

    case $resource in
	pod*)
	    pod_to_delete=$(oc_exec_local get pods | awk "/${resource_name}-[0-9]+-[^b][^u][^i][^l][^d].*Running/ { print \$1; }")
	    [ -z "$pod_to_delete" ] && die "Couln't find $resource $resource_name"
	    CMD="oc delete pod $pod_to_delete"
	    ;;
    esac
    show_comment "Removind resource $resource $resource_name" "$CMD"
    oc_exec_local $CMD || die "Error while removingresources: $resources"
    pause
}


function oc_set_env_for() {
    local args=$1

    CMD="oc env $args"
    show_comment "Setting Database environemnt for deployment descriptor" "$CMD"
    oc_exec_local \
	$CMD \
	    || die "Error while setting environmet for $args"
}

function oc_test_connection() {
    local resource_type=$1
    local resource_name=$2
    local find_resource=$(oc_exec_local "get $resource_type -n $PROJECT_NAME $resource_name --template '{{.spec.clusterIP}}:{{index .spec.ports 0 \"port\"}}'")
    local u
    local ssh_host

    CMD="curl -s $find_resource"
    pause
    show_comment "Testing Service" "$CMD"
    if [ "$USER" = "$(oc whoami)" ] ; then
	u=$USER
    else
	u=root
    fi
    exec_remote_command \
	$CMD
    pause
}

function exec_remote_command() {
    local ssh_host
    local inet4

    if [ -z "$MASTER_NODE" ] ; then
	ssh_host="${OSE_NAME_PREFIX}${OSE_VER}-master01"
    else
	ssh_host=$MASTER_NODE
    fi
    echo $MASTER_NODE | grep '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' > /dev/null && {
	inet4=$MASTER_NODE 
    } || {
	inet4=$(dig +short $(host -t a -4 $MASTER_NODE | awk ' { print $1; } '))
    }
    ip a sh | grep $inet4 > /dev/null && ssh_host="localhost"
    if [ "$ssh_host" = "localhost" ] ; then
	eval "$*"
    else
	ssh -qt $u@$ssh_host \
	    "$*"
    fi
}

function oc_watch_for_resource() {
    local resource_type=$1

    CMD="oc get -w $resource_type"
    show_comment "Watching for resources $resource_type" "$CMD"
    oc_exec_local \
	$CMD
    pause
}

function show_env() {
    local env_regex=$*

    for r in $env_regex ; do
	env | grep $r | sort
    done
}