#!/usr/bin/env bash
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

# Make sure that bash version meets the pre-requisite

if [[ -z "${BASH_VERSINFO}" ]] \
   || [[ "${BASH_VERSINFO[0]}" -lt 3 ]] \
   || [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]}" -lt 2 ]]; then
  echo "bash v3.2+ is required. Sorry."
  exit 1
fi

this="${BASH_SOURCE-$0}"
BINDIR=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)
#shellcheck disable=SC2034
QATESTMODE=false

. "${BINDIR}/core.d/common.sh"

# dummy functions
function add_vote_table
{
  true
}

function add_footer_table
{
  true
}

function big_console_header
{
  true
}

function add_test
{
  true
}

## @description  Clean the filesystem as appropriate and then exit
## @audience     private
## @stability    evolving
## @replaceable  no
## @param        runresult
function cleanup_and_exit
{
  local result=$1

  if [[ ${PATCH_DIR} =~ ^/tmp/yetus
    && -d ${PATCH_DIR} ]]; then
    rm -rf "${PATCH_DIR}"
  fi

  # shellcheck disable=SC2086
  exit ${result}
}

## @description  Setup the default global variables
## @audience     public
## @stability    stable
## @replaceable  no
function setup_defaults
{
  common_defaults
}

## @description  Print the usage information
## @audience     public
## @stability    stable
## @replaceable  no
function yetus_usage
{
  echo "Usage: apply-patch.sh [options] patch-file | issue-number | http"
  echo
  echo "--debug                If set, then output some extra stuff to stderr"
  echo "--dry-run              Check for patch viability without applying"
  echo "--modulelist=<list>    Specify additional modules to test (comma delimited)"
  echo "--offline              Avoid connecting to the Internet"
  echo "--patch-dir=<dir>      The directory for working and output files (default '/tmp/yetus-(random))"
  echo "--plugins=<dir>        A directory of user provided plugins. see test-patch.d for examples (default empty)"
  echo "--skip-system-plugins  Do not load plugins from ${BINDIR}/test-patch.d"
  echo ""
  echo "Shell binary overrides:"
  echo "--awk-cmd=<cmd>        The 'awk' command to use (default 'awk')"
  echo "--curl-cmd=<cmd>       The 'curl' command to use (default 'curl')"
  echo "--diff-cmd=<cmd>       The GNU-compatible 'diff' command to use (default 'diff')"
  echo "--file-cmd=<cmd>       The 'file' command to use (default 'file')"
  echo "--git-cmd=<cmd>        The 'git' command to use (default 'git')"
  echo "--grep-cmd=<cmd>       The 'grep' command to use (default 'grep')"
  echo "--patch-cmd=<cmd>      The 'patch' command to use (default 'patch')"
  echo "--sed-cmd=<cmd>        The 'sed' command to use (default 'sed')"

  importplugins

  unset TESTFORMATS
  unset PLUGINS
  unset BUILDTOOLS

  for plugin in ${BUGSYSTEMS}; do
    if declare -f ${plugin}_usage >/dev/null 2>&1; then
      echo
      "${plugin}_usage"
    fi
  done
}

## @description  Interpret the command line parameters
## @audience     private
## @stability    stable
## @replaceable  no
## @params       $@
## @return       May exit on failure
function parse_args
{
  local i

  common_args "$@"

  for i in "$@"; do
    case ${i} in
      --dry-run)
        PATCH_DRYRUNMODE=true
      ;;
      --*)
        ## PATCH_OR_ISSUE can't be a --.  So this is probably
        ## a plugin thing.
        continue
      ;;
      *)
        PATCH_OR_ISSUE=${i#*=}
      ;;
    esac
  done

  if [[ ! -d ${PATCH_DIR} ]]; then
    mkdir -p "${PATCH_DIR}"
    if [[ $? != 0 ]] ; then
      yetus_error "ERROR: Unable to create ${PATCH_DIR}"
      cleanup_and_exit 1
    fi
  fi
}

trap "cleanup_and_exit 1" HUP INT QUIT TERM

setup_defaults

parse_args "$@"

importplugins
yetus_debug "Removing BUILDTOOLS, PLUGINS, and TESTFORMATS from installed plug list"
unset BUILDTOOLS
unset PLUGINS
unset TESTFORMATS

parse_args_plugins "$@"

plugins_initialize

locate_patch

patchfile_dryrun_driver "${PATCH_DIR}/patch"
RESULT=$?

if [[ ${RESULT} -gt 0 ]]; then
  yetus_error "ERROR: Aborting! ${PATCH_OR_ISSUE} cannot be verified."
  cleanup_and_exit ${RESULT}
fi

if [[ ${PATCH_DRYRUNMODE} == false ]]; then
  patchfile_apply_driver "${PATCH_DIR}/patch"
  RESULT=$?
fi

cleanup_and_exit ${RESULT}
