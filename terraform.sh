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
#trap echo EXIT


#### This is for AWS setup
# 1. remote state set to AWS S3
# 2. there are regional and global layers

#### When there are no AWS accounts to use then default account is "default"


REMOTE_STATES_REGION=${REMOTE_STATES_REGION:-"eu-west-1"}
REMOTE_STATES_PREFIX=${REMOTE_STATES_PREFIX:-"tf-states."}

AWS_ACCOUNT_ALIAS=${TF_AWS_ACCOUNT_ALIAS:-"default"}
AWS_REGION=${TF_AWS_REGION:-""}
INFRASTRUCTURE_LAYER=${INFRASTRUCTURE_LAYER:-""}
LAYER_VERSION=${LAYER_VERSION:-""}

# first things first: parse command line
while :; do
    case $1 in
        --account)
            if [ -n "$2" ]; then
                AWS_ACCOUNT_ALIAS=$2
                shift
            else
                printf 'ERROR: "--account" requires a non-empty option argument.\n' >&2
                exit 1
            fi
            ;;
        --region)
            if [ -n "$2" ]; then
                AWS_REGION=$2
                shift
            else
                printf 'ERROR: "--region" requires a non-empty option argument.\n' >&2
                exit 1
            fi
            ;;
        --layer)
            if [ -n "$2" ]; then
                INFRASTRUCTURE_LAYER=$2
                shift
            else
                printf 'ERROR: "--layer" requires a non-empty option argument.\n' >&2
                exit 1
            fi
            ;;
        --layer-version)
            if [ -n "$2" ]; then
                LAYER_VERSION=$2
                shift
            else
                printf 'ERROR: "--layer-version" requires a non-empty option argument.\n' >&2
                exit 1
            fi
            ;;
        -\?|--help)
            show_help
            exit 0
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)               # Default case: If no more options then break out of the loop.
            AWS_ACCOUNT_ALIAS=$1
            AWS_REGION=$2
            INFRASTRUCTURE_LAYER=$3
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

#####

#echo $ACCOUNT_WORK_DIR



script_check() {
  test -z "$AWS_ACCOUNT_ALIAS" && die "AWS account alias is not set."
  test ! -d "${ACCOUNT_WORK_DIR}" && die "AWS account work directory (${ACCOUNT_WORK_DIR}) does not exist."
  test -z "$AWS_REGION" && die "AWS region is not set."
  test -z "$INFRASTRUCTURE_LAYER" && die "Layer is not set."
#  test -z "$LAYER_VERSION" && die "Layer version is not set."

  test -z "$REMOTE_STATES_REGION" && die "Remote states region is not set."
  test -z "$REMOTE_STATES_PREFIX" && die "Remote states prefix is not set."

  if ! exists terragrunt; then die "Can't find 'terragrunt' in PATH. Run 'brew install terragrunt' or whatever works for you."; fi
}

# check if everything is okay
script_check


cd $ACCOUNT_WORK_DIR

echo
msg_info "Working directory: `pwd`"
echo

if [ $# -lt 1 ]; then
  echo "ERROR: Missing action (init, plan, apply, output, etc)"
  exit 1
fi

TF_RUNNABLE_BIN=$(terrabin)

function run_tf() {
  msg_info "Running command: $TF_RUNNABLE_BIN $@"
  echo

  $TF_RUNNABLE_BIN "$@" 1>&2
}


tf_init() {

  rm -rf ${terraform_work_dir}/*
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
    echo
    #curl -Ls https://github.com/gruntwork-io/terragrunt/releases/download/v0.1.0/terragrunt_darwin_386 -o /usr/local/bin/terragrunt && chmod 755 /usr/local/bin/terragrunt
    echo "Dude, don't be lazy and install terragrunt 0.1.0 or newer :)"
    echo "Continuing with 'terraform remote config'..."
    echo

    terraform remote config\
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

case "$action" in
  init) ;;
  init-no-refresh) ;;
  plan) ;;
  plan-no-refresh) ;;
  apply) ;;
  apply-no-refresh) ;;
  apply-plan) ;;
  plan-destroy) ;;
  destroy) ;;
  refresh) ;;
  taint) ;;
  untaint) ;;
  validate) ;;
  output) ;;
  show) ;;
  graph) ;;
#  *)
#    show_help
#    exit 1
esac


cat <<EOF
---------------------------------------------------------
AWS account alias:   $AWS_ACCOUNT_ALIAS
AWS region:          $AWS_REGION
Layer name:          $INFRASTRUCTURE_LAYER
Layer version:       $LAYER_VERSION
---------------------------------------------------------
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
  msg_warn "Layer '${INFRASTRUCTURE_LAYER}' should be initiated before use!"
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

#echo $region_infrastructure_layer_var_file
#echo $infrastructure_layer_var_file

# Check if "region/infrastructure layer" var file exists, then include it in commands
if [ -n "${region_infrastructure_layer_var_file}" ]; then
  if [[ -f "${PROJECT_ROOT_DIR}/accounts/${AWS_ACCOUNT_ALIAS}/${region_infrastructure_layer_var_file}" ]]; then
    msg_info "region_infrastructure_layer_var_file:" $region_infrastructure_layer_var_file
    region_infrastructure_layer_var_file="-var-file=../../${region_infrastructure_layer_var_file}"
  else
    msg_fatal "Missing required tfvars file: accounts/${AWS_ACCOUNT_ALIAS}/${region_infrastructure_layer_var_file}"
    exit 1
  fi
fi

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


# Set terraform variables
export TF_VAR_remote_states_bucket=$remote_states_bucket
export TF_VAR_remote_states_region=$remote_states_region

# Variables defining group of resources to manage (account + region + layer + version)
export TF_VAR_aws_account_alias=$AWS_ACCOUNT_ALIAS
export TF_VAR_aws_region=$AWS_REGION
export TF_VAR_infrastructure_layer=$INFRASTRUCTURE_LAYER
export TF_VAR_layer_version=$LAYER_VERSION


if [[ "$action" == "init" || "$action" == "init-no-refresh" ]]; then
  tf_init
fi

if [ "$action" == "plan" ]; then

  if [ -z $NOT_DETAILED_EXITCODE ]; then # CircleCI only understands exitcode 0 or 1
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
    echo "ERROR: Omg! There was an error during plan."
    exit 1
  fi
fi

if [ "$action" == "apply-plan" ]; then
  run_tf apply \
    $arguments

  exit $?
fi

if [ "$action" == "show" ]; then
  run_tf show \
    $arguments

  exit $?
fi

if [ "$action" == "validate" ] || [ "$action" == "fmt" ]; then
  run_tf $action \
    $LAYER_WORK_DIR

  exit $?
fi

if [ "$action" == "taint" ] || [ "$action" == "untaint" ]; then
  run_tf $action \
    $arguments

  exit $?
fi

if [ "$action" == "output" ]; then
  run_tf output \
    $arguments

  exit $?
fi


if [ "$action" == "graph" ]; then
  detectOS
  terraform graph -draw-cycles $LAYER_WORK_DIR | dot -Tpng -o graph.png
  if [[ ${platform} == 'linux' ]]; then
    xdg-open graph.png
  elif [[ ${platform} == 'macos' ]]; then
    open graph.png
  elif [[ ${platform} == 'unknown' ]]; then
    echo "Not able to detect OS, exiting..."
    exit 1
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
    echo "File s3://${remote_states_bucket}/${terraform_state_key} does not seem to exist in region ${remote_states_region}"
    exit 1
  fi

  rm -rf ${terraform_work_dir}
fi
