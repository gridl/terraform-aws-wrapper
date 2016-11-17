#!/usr/bin/env bash

#set -e

# import global functions
BASE_DIR=$(dirname "$0")
. "$BASE_DIR/common_functions.sh" || {
  echo "Error including common functions."
  exit 1
}

# import variables
BASE_DIR=$(dirname "$0")
. "$BASE_DIR/common_variables.sh" || {
  echo "Error including common variables."
  exit 1
}

export TF_MODULE_DEPTH=-1

export TERRAGRUNT_DEBUG=true # related issue - https://github.com/gruntwork-io/terragrunt/issues/36

# Ensure script console output is separated by blank line at top and bottom to improve readability
trap echo EXIT


#### This is for AWS setup
# 1. remote state set to AWS S3
# 2. there are regional and global layers

#### When there are no AWS accounts to use then default account is "default"


REMOTE_STATES_REGION=${REMOTE_STATES_REGION:-"eu-west-1"}
REMOTE_STATES_PREFIX=${REMOTE_STATES_PREFIX:-"tf-states."}

#AWS_ACCOUNT_ALIAS=${AWS_ACCOUNT_ALIAS:-""}
#AWS_REGION=${AWS_REGION:-""}
#INFRASTRUCTURE_LAYER=${INFRASTRUCTURE_LAYER:-""}
#LAYER_VERSION=${LAYER_VERSION:-""}

# CircleCI only understands boolean exit codes (0 and 1), so exit code 2 means an error
PLAN_SIMPLE_EXITCODE=${PLAN_SIMPLE_EXITCODE:-""}


#####
# Group of Terraform actions
terraform_actions_with_arguments=(show output taint untaint state import)
terraform_actions_with_tf_dir=(validate fmt)

# first things first: parse command line
while :; do
    case $1 in
        --account)
            if [ -n "$2" ]; then
                AWS_ACCOUNT_ALIAS=$2
                shift
            fi
            ;;
        --region)
            if [ -n "$2" ]; then
                AWS_REGION=$2
                shift
            fi
            ;;
        --layer)
            if [ -n "$2" ]; then
                INFRASTRUCTURE_LAYER=$2
                shift
            fi
            ;;
        --layer-version)
            if [ -n "$2" ]; then
                LAYER_VERSION=$2
                shift
            fi
            ;;
        -\?|--help)
            show_help
            exit 0
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)               # Default case: If no more options then break out of the loop and accept short form of arguments.
#echo "!!!!!"
#echo $AWS_ACCOUNT_ALIAS
AWS_ACCOUNT_ALIAS=${AWS_ACCOUNT_ALIAS:-"$1"}
#echo $AWS_ACCOUNT_ALIAS
AWS_REGION=${AWS_REGION:-"$2"}
INFRASTRUCTURE_LAYER=${INFRASTRUCTURE_LAYER:-"$3"}
LAYER_VERSION=${LAYER_VERSION:-""}
shift 3
            break
    esac

    shift
done

# Location where state files for project should be created or loaded from
remote_states_bucket="${REMOTE_STATES_PREFIX}${AWS_ACCOUNT_ALIAS}"
remote_states_region=$REMOTE_STATES_REGION

###########

ACCOUNT_WORK_DIR="${PROJECT_ROOT_DIR}/accounts/${AWS_ACCOUNT_ALIAS}"
LAYER_WORK_DIR="${PROJECT_ROOT_DIR}/layers/${AWS_ACCOUNT_ALIAS}/${INFRASTRUCTURE_LAYER}"

###########
# check if everything is okay
###########
test -z "$AWS_ACCOUNT_ALIAS" && die "AWS account alias is not set."
test ! -d "${ACCOUNT_WORK_DIR}" && die "AWS account work directory (${ACCOUNT_WORK_DIR}) does not exist."
test -z "$AWS_REGION" && die "AWS region is not set."
test -z "$INFRASTRUCTURE_LAYER" && die "Layer is not set."
#  test -z "$LAYER_VERSION" && die "Layer version is not set."
test -z "$REMOTE_STATES_REGION" && die "Remote states region is not set."
test -z "$REMOTE_STATES_PREFIX" && die "Remote states prefix is not set."

if ! exists terragrunt; then msg_warn "Can't find 'terragrunt' in PATH. Are you sure that 'terragrunt' is installed?"; echo; sleep 5; fi


cd $ACCOUNT_WORK_DIR

echo
msg_info "Working directory: `pwd`"
echo

if [ $# -lt 1 ]; then
  die "Missing argument action (init, plan, apply, output, etc)"
fi


tf_init() {

  rm -rf ${terraform_work_dir}
  mkdir -p ${terraform_work_dir}
  cd ${terraform_work_dir}

  if [ -z $CI ]; then # less output for CI is probably a good idea, but we'll see
    echo
    msg_info "Bucket: $remote_states_bucket ; Region: $remote_states_region"
    echo

    set +e # do not stop if bucket does not exist
    aws s3 ls $remote_states_bucket --region $remote_states_region
    if [ $? -ne 0 ]; then
      # Need to create bucket until this issue is done in terragrunt - https://github.com/gruntwork-io/terragrunt/issues/35
      aws s3api create-bucket --bucket $remote_states_bucket --acl private --create-bucket-configuration LocationConstraint=$remote_states_region --region $remote_states_region
      aws s3api put-bucket-versioning --bucket $remote_states_bucket --versioning-configuration Status=Enabled --region $remote_states_region

      if [ $? -eq 0 ]; then
        msg_info "Bucket has been created"
      else
        die "Bucket $remote_states_bucket could not be created"
      fi
    fi
    set -e

    echo
  fi

  cat <<EOF > .terragrunt
lock = {
  backend = "dynamodb"
  config {
    state_file_id = "${remote_states_bucket}_${terraform_state_key}"
    aws_region = "${remote_states_region}"
    table_name = "terragrunt_locks"
  }
}

remote_state = {
  backend = "s3"
  config {
    encrypt = "true"
    bucket = "${remote_states_bucket}"
    region = "${remote_states_region}"
    key = "${terraform_state_key}"
  }
}
EOF

  if ! exists terragrunt; then
    run_tf_only remote config\
      -backend=s3\
      -backend-config="bucket=$remote_states_bucket"\
      -backend-config="region=$remote_states_region"\
      -backend-config="key=${terraform_state_key}"\
      -backend-config="encrypt=true"\
      -pull=true
  fi

  run_tf get \
    $LAYER_WORK_DIR

  if [ "$action" == "init" ]; then
    run_tf refresh \
      $infrastructure_layer_var_file \
      $region_infrastructure_layer_var_file \
      $arguments \
      $LAYER_WORK_DIR
  fi

  touch ${terraform_state_key}.txt

  exit 0
}

action="$1"
arguments="${*:2}"
destroy=""
force=""
refresh=""

cat <<EOF
----------------------------------------------------------
AWS account alias:   $AWS_ACCOUNT_ALIAS
AWS region:          $AWS_REGION
Layer name:          $INFRASTRUCTURE_LAYER
Layer version:       $LAYER_VERSION
----------------------------------------------------------
EOF

msg_info "Terraform action:" $action
if [ -n "$arguments" ]; then
  msg_info "Terraform extra arguments:" $arguments
fi

if contains_element "$INFRASTRUCTURE_LAYER" "${ALLOWED_GLOBAL_LAYERS[@]}"; then
  terraform_state_key="${INFRASTRUCTURE_LAYER}"
  region_infrastructure_layer_var_file=""
elif [ -n "${LAYER_VERSION}" ]; then
  terraform_state_key="${AWS_REGION}_${INFRASTRUCTURE_LAYER}_${LAYER_VERSION}"
  region_infrastructure_layer_var_file=${INFRASTRUCTURE_LAYER}.${AWS_REGION}.tfvars
else
  terraform_state_key="${AWS_REGION}_${INFRASTRUCTURE_LAYER}"
  region_infrastructure_layer_var_file=${INFRASTRUCTURE_LAYER}.${AWS_REGION}.tfvars
fi

terraform_work_dir=${ACCOUNT_WORK_DIR}/.layers/${terraform_state_key}

if [[ ! -e "${terraform_work_dir}/${terraform_state_key}.txt" && "$action" != "init"* ]]; then
  msg_fatal "Layer '${INFRASTRUCTURE_LAYER}' should be initiated before use!"
  if contains_element "$INFRASTRUCTURE_LAYER" "${ALLOWED_GLOBAL_LAYERS[@]}"; then
    msg_info "Run this: $0 --account ${AWS_ACCOUNT_ALIAS} --layer ${INFRASTRUCTURE_LAYER} init"
  elif [ -n "${TF_VAR_layer_version}" ]; then
    msg_info "Run this: $0 --account ${AWS_ACCOUNT_ALIAS} --region ${AWS_REGION} --layer ${INFRASTRUCTURE_LAYER} --version ${LAYER_VERSION} init"
  else
    msg_info "Run this: $0 --account ${AWS_ACCOUNT_ALIAS} --region ${AWS_REGION} --layer ${INFRASTRUCTURE_LAYER} init"
  fi
  exit 1
fi


# Check if "infrastructure layer" var file exists, then include it in commands
if [ -e "${INFRASTRUCTURE_LAYER}.tfvars" ]; then
  infrastructure_layer_var_file="-var-file=../../${INFRASTRUCTURE_LAYER}.tfvars"
fi

# Check if "region/infrastructure layer" var file exists, then include it in commands
if [ -n "${region_infrastructure_layer_var_file}" ]; then
  if [[ -f "${PROJECT_ROOT_DIR}/accounts/${AWS_ACCOUNT_ALIAS}/${region_infrastructure_layer_var_file}" ]]; then
    msg_info "region_infrastructure_layer_var_file:" $region_infrastructure_layer_var_file
    region_infrastructure_layer_var_file="-var-file=../../${region_infrastructure_layer_var_file}"
  else
    die "Missing required tfvars file: accounts/${AWS_ACCOUNT_ALIAS}/${region_infrastructure_layer_var_file}"
  fi
fi

# Set Terraform variables
export TF_VAR_remote_states_bucket=$remote_states_bucket
export TF_VAR_remote_states_region=$remote_states_region

# Variables defining group of resources to manage (account + region + layer + version)
export TF_VAR_aws_account_alias=$AWS_ACCOUNT_ALIAS
export TF_VAR_aws_region=$AWS_REGION
export TF_VAR_infrastructure_layer=$INFRASTRUCTURE_LAYER
export TF_VAR_layer_version=$LAYER_VERSION

if [[ -d "${terraform_work_dir}" ]]; then
  cd ${terraform_work_dir}
fi

if [ "$action" == "plan-destroy" ]; then
  action="plan"
  destroy="-destroy"
  refresh="-refresh=true"
fi

if [ "$action" == "plan-no-refresh" ]; then
  action="plan"
  refresh="-refresh=false"
fi

if [ "$action" == "apply" ]; then
  refresh="-refresh=true"
fi

if [ "$action" == "apply-no-refresh" ]; then
  action="apply"
  refresh="-refresh=false"
fi

if [ "$action" == "destroy" ]; then
  destroy="-destroy"
  force="-force"
fi

#########################################

if [[ "$action" == "init" || "$action" == "init-no-refresh" ]]; then
  tf_init
fi

if [ "$action" == "plan" ]; then

  if [ -z $PLAN_SIMPLE_EXITCODE ]; then
    detailed_exitcode="-detailed-exitcode"
  else
    detailed_exitcode=""
  fi

  # Related issue "-detailed-exitcode" is not respected - https://github.com/gruntwork-io/terragrunt/issues/37
  run_tf plan \
    $refresh \
    $destroy \
    -input=false \
    $detailed_exitcode \
    $infrastructure_layer_var_file \
    $region_infrastructure_layer_var_file \
    $arguments \
    $LAYER_WORK_DIR

  EXIT_CODE=$?

  if [ $EXIT_CODE == 0 ]; then
    exit 0
  elif [ $EXIT_CODE == 2 ]; then
    echo "Nice! There are changes which you can apply."
    exit 0
  else
    die "ERROR: Omg! There was an error during plan."
  fi
fi

# Example: ./terraform.sh ... apply-plan filename.plan
if [ "$action" == "apply-plan" ]; then
  run_tf apply \
    $arguments

  exit $?
fi

if contains_element "$action" "${terraform_actions_with_arguments[@]}"; then
  run_tf $action \
    $arguments

  exit $?
fi

if contains_element "$action" "${terraform_actions_with_tf_dir[@]}"; then
  run_tf $action \
    $LAYER_WORK_DIR

  exit $?
fi

if [ "$action" == "graph" ]; then
  terraform graph -draw-cycles $LAYER_WORK_DIR | dot -Tpng -o graph.png

  if [[ "`uname`" == 'Linux' ]]; then
    xdg-open graph.png
  elif [[ "`uname`" == 'Darwin' ]]; then
    open graph.png
  else
    die "Windows? I have bad news for you..."
  fi

  exit 0
fi

# Execute the terraform action (apply, destroy, refresh)
run_tf "$action" \
  -input=false \
  $infrastructure_layer_var_file \
  $region_infrastructure_layer_var_file \
  $refresh \
  $force \
  $arguments \
  $LAYER_WORK_DIR

# Destroy layer should remove state file from S3 also (@todo: check if destroy was successfull before deleting state file from S3)
if [ "$action" == "destroy" ]; then

  set +e # do not stop if bucket does not exist
  aws s3 rm s3://${remote_states_bucket}/${terraform_state_key} --region ${remote_states_region}
  set -e

  if [ $? -eq 0 ]; then
    echo "File s3://${remote_states_bucket}/${terraform_state_key} has been removed"
  else
    die "File s3://${remote_states_bucket}/${terraform_state_key} does not seem to exist in region ${remote_states_region}"
  fi

  rm -rf ${terraform_work_dir}
fi
