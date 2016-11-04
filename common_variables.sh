#!/bin/bash

# Global variables
#ALLOWS_VARFILE=(apply plan push refresh destroy)
#ALLOWED_AWS_REGIONS=(us-west-2 eu-west-1)
#GLOBAL_AWS_REGION=eu-west-1
#REMOTE_STATES_REGION=eu-west-1
#REMOTE_STATES_PREFIX="tf-states."
#LAYERS_WITH_ALLOWED_EMPTY_VERSION=(global shared application legacy s3_artifacts ci_cd)

ALLOWED_GLOBAL_LAYERS=(global)

PROJECT_ROOT_DIR="$(pwd)/example"

#AWS_ACCOUNT_ALIAS=$1
#INFRASTRUCTURE_LAYER=$2 # global, us-west-2.shared-aws , us-west-2.application.development , eu-west-1 application feature1
#LAYER_VERSION= # feature1, staging, production

#region_infrastructure_layer_var_file=""

# AWS account
# @todo
#if [[ "x${AWS_ACCOUNT_ALIAS}" == "x" || ! -d accounts/${AWS_ACCOUNT_ALIAS} ]]; then
#  msg_error "no AWS_ACCOUNT_ALIAS set!"
#  show_help
#fi

#if [[ "x${INFRASTRUCTURE_LAYER}" == "x" ]]; then
#  msg_error "no INFRASTRUCTURE_LAYER set!"
#  show_help
#fi
#
#shift # account

# Layer/region
#if [[ "${INFRASTRUCTURE_LAYER}" == "global" || "${INFRASTRUCTURE_LAYER}" == "legacy" ]]; then
#  AWS_REGION=$DEFAULT_AWS_REGION
#  shift # layer
#else
#  if contains_element "$1" "${ALLOWED_AWS_REGIONS[@]}"; then
#    AWS_REGION=$1
#  else
#    echo "ERROR: Unsupported region: $1"
#    exit 1
#  fi
#
#  shift # region
#
#  # Layer is before "."
#  INFRASTRUCTURE_LAYER=$(echo $1 | cut -d "." -f 1)
#
#  # Version is after "."
#  LAYER_VERSION=$(echo $1 | cut -d "." -sf 2 | tr '[/\.]' '_')
#
#  if contains_element "$INFRASTRUCTURE_LAYER" "${LAYERS_WITH_ALLOWED_EMPTY_VERSION[@]}"; then
#    if [ ! -z $LAYER_VERSION ]; then
#      echo "ERROR: Layer '$INFRASTRUCTURE_LAYER' should not be versioned. Probably you need to use layer named '$INFRASTRUCTURE_LAYER'"
#      exit 1
#    fi
#  elif [ -z $LAYER_VERSION ]; then
#    echo "ERROR: Layer '$INFRASTRUCTURE_LAYER' should be versioned. Use '.' as separator before version. For example, $INFRASTRUCTURE_LAYER.my-feature-branch"
#    exit 1
#  fi
#
#  region_infrastructure_layer_var_file=${INFRASTRUCTURE_LAYER}.${AWS_REGION}.tfvars
#
#  if [[ ! -f accounts/${AWS_ACCOUNT_ALIAS}/${region_infrastructure_layer_var_file} ]]; then
#    echo "ERROR: Missing required tfvars file: accounts/${AWS_ACCOUNT_ALIAS}/${region_infrastructure_layer_var_file}"
#    exit 1
#  fi
#
#  shift # layer
#fi

# Check if AWS profile name matches account alias when running not on CI server
# (consider switching profiles automatically using `awsp` or `aws-vault`)
#if [ -z $CI ] && [[ "$AWS_DEFAULT_PROFILE" != "$AWS_ACCOUNT_ALIAS"* ]]; then
#  echo "ERROR: AWS_DEFAULT_PROFILE ('$AWS_DEFAULT_PROFILE') should start with specified account alias ('$AWS_ACCOUNT_ALIAS')."
#  exit 1
#fi
