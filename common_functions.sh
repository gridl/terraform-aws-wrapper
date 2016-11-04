#!/usr/bin/env bash

MYNAME=$(basename $0)

die() {
  msg_fatal "$@"
  exit 1
}

msg_info() {
  local msg="INFO:  $@"
  msg_log "$(time_s) $msg"
  echo "$msg"
}

msg_warn() {
  local msg="WARN:  $@"
  msg_log "$msg"
  echo "$(time_s) $msg"
}

msg_error() {
  local msg="ERROR: $@"
  msg_log "$msg"
  echo "$(time_s) $msg" 1>&2
}

msg_fatal() {
  local msg="FATAL: $@"
  msg_log "$msg"
  echo "$(time_s) $msg" 1>&2
}

msg_log() {
  logger -i -t "$MYNAME" "$@"
}

time_s() {
  local millis=$(($(date +%N)/1000000))
  date +"[%Y/%m/%d %H:%M:%S.${millis}] "
}


######


show_help() {
  echo -n "
  Usage:
    $0 [account] global [action] [arguments]
    $0 [account] [region] [layer] [action] [arguments]
    $0 [account] [region] [service.version] [action] [arguments]

  Accounts (AWS account aliases):
    company-dev, company-staging, company-prod, company-infra, company-legacy

  Region:
    us-west-2, eu-west-1

  Layer:
    legacy - All resources exposed from legacy AWS account (Route53 and VPC). Read-only.
    global - Global resources for the whole AWS account
    shared - Shared resources within one AWS region
    application - Application resources withing one AWS region,
                  sharing same 'shared' layer
    [service.version] - Specific service, which resides within application. For eg, spellchecker, salton, etc.
                        Service should contain dot to specify version of layer to manage (eg, 'salton.feature-branch').

  Action:
    init
    plan
    play-no-refresh
    apply
    apply-no-refresh
    plan-destroy
    destroy
    refresh
    taint
    untaint
    validate
    output
    show
    graph

  Examples:
    $0 company-dev global init
    $0 company-dev global plan -var key=value
    $0 company-dev us-west-2 shared plan
    $0 company-dev us-west-2 application plan
    $0 company-dev us-west-2 application apply -var key=value
    $0 company-dev us-west-2 service1.dev plan
    $0 company-dev us-west-2 service1.feature-branch plan
"

  exit 1
}


contains_element () {
  local i

  for i in "${@:2}"; do
    [[ "$i" == "$1" ]] && return 0
  done

  return 1
}

debug() {
  if [[ $SHOW_TF_DEBUG == "1" ]]; then
    echo "`date '+%F %T'` - $*"
  fi
}

function detectOS {
    platform='unknown'
    unamestr=`uname`
    if [[ "$unamestr" == 'Linux' ]]; then
       platform='linux'
    elif [[ "$unamestr" == 'Darwin' ]]; then
       platform='macos'
    fi
}

function exists() {
  command -v "$1" >/dev/null 2>&1
}

function terrabin() {
  if exists terragrunt; then
    echo "terragrunt"
  elif exists terraform; then
    echo "terraform"
  fi
}


