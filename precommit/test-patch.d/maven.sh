#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

declare -a MAVEN_ARGS=("--batch-mode")
declare -a MAVEN_ALREADY=()
declare -a MAVEN_NEWLIST=()

if [[ -z "${MAVEN_HOME:-}" ]]; then
  MAVEN=mvn
else
  MAVEN=${MAVEN_HOME}/bin/mvn
fi

MAVEN_CUSTOM_REPOS=false
MAVEN_CUSTOM_REPOS_DIR="${HOME}/yetus-m2"
MAVEN_DEPENDENCY_ORDER=true

add_test_type mvnsite
add_test_type mvneclipse
add_build_tool maven

function maven_usage
{
  yetus_add_option "--mvn-cmd=<cmd>" "The 'mvn' command to use (default \${MAVEN_HOME}/bin/mvn, or 'mvn')"
  yetus_add_option "--mvn-custom-repos" "Use per-project maven repos"
  yetus_add_option "--mvn-custom-repos-dir=dir" "Location of repos, default is '${MAVEN_CUSTOM_REPOS_DIR}'"
  yetus_add_option "--mvn-deps-order=<bool>" "Disable maven's auto-dependency module ordering (Default: '${MAVEN_DEPENDENCY_ORDER}')"
  yetus_add_option "--mvn-settings=file" "File to use for settings.xml"
}

function maven_parse_args
{
  local i

  for i in "$@"; do
    case ${i} in
      --mvn-cmd=*)
        MAVEN=${i#*=}
      ;;
      --mvn-custom-repos)
        MAVEN_CUSTOM_REPOS=true
      ;;
      --mvn-custom-repos-dir=*)
        MAVEN_CUSTOM_REPOS_DIR=${i#*=}
      ;;
      --mvn-deps-order=*)
        MAVEN_DEPENDENCY_ORDER=${i#*=}
      ;;
      --mvn-settings=*)
        MAVEN_SETTINGS=${i#*=}
        if [[ -f ${MAVEN_SETTINGS} ]]; then
          MAVEN_ARGS=("${MAVEN_ARGS[@]}" "--settings=${MAVEN_SETTINGS}")
        else
          yetus_error "WARNING: ${MAVEN_SETTINGS} not found. Ignoring."
        fi
      ;;
    esac
  done

  if [[ ${OFFLINE} == "true" ]]; then
    MAVEN_ARGS=("${MAVEN_ARGS[@]}" --offline)
  fi
}

function maven_initialize
{
  # we need to do this before docker does it as root

  if [[ ! ${MAVEN_CUSTOM_REPOS_DIR} =~ ^/ ]]; then
    yetus_error "ERROR: --mvn-custom-repos-dir must be an absolute path."
    return 1
  fi

  if [[ ${MAVEN_CUSTOM_REPOS} = true ]]; then
    MAVEN_LOCAL_REPO="${MAVEN_CUSTOM_REPOS_DIR}"
    if [[ -e "${MAVEN_CUSTOM_REPOS_DIR}"
       && ! -d "${MAVEN_CUSTOM_REPOS_DIR}" ]]; then
      yetus_error "ERROR: ${MAVEN_CUSTOM_REPOS_DIR} is not a directory."
      return 1
    elif [[ ! -d "${MAVEN_CUSTOM_REPOS_DIR}" ]]; then
      yetus_debug "Creating ${MAVEN_CUSTOM_REPOS_DIR}"
      mkdir -p "${MAVEN_CUSTOM_REPOS_DIR}"
    fi
  fi

  if [[ -e "${HOME}/.m2"
     && ! -d "${HOME}/.m2" ]]; then
    yetus_error "ERROR: ${HOME}/.m2 is not a directory."
    return 1
  elif [[ ! -e "${HOME}/.m2" ]]; then
    yetus_debug "Creating ${HOME}/.m2"
    mkdir -p "${HOME}/.m2"
  fi
}

function maven_precheck
{
  declare logfile="${PATCH_DIR}/mvnrepoclean.log"
  declare line

  if [[ ! ${MAVEN_CUSTOM_REPOS_DIR} =~ ^/ ]]; then
    yetus_error "ERROR: --mvn-custom-repos-dir must be an absolute path."
    return 1
  fi

  if [[ ${MAVEN_CUSTOM_REPOS} = true ]]; then
    MAVEN_LOCAL_REPO="${MAVEN_CUSTOM_REPOS_DIR}/${PROJECT_NAME}-${PATCH_BRANCH}-${INSTANCE}"
    if [[ -e "${MAVEN_LOCAL_REPO}"
       && ! -d "${MAVEN_LOCAL_REPO}" ]]; then
      yetus_error "ERROR: ${MAVEN_LOCAL_REPO} is not a directory."
      return 1
    fi

    if [[ ! -d "${MAVEN_LOCAL_REPO}" ]]; then
      yetus_debug "Creating ${MAVEN_LOCAL_REPO}"
      mkdir -p "${MAVEN_LOCAL_REPO}"
      if [[ $? -ne 0 ]]; then
        yetus_error "ERROR: Unable to create ${MAVEN_LOCAL_REPO}"
        return 1
      fi
    fi
    touch "${MAVEN_LOCAL_REPO}"

    # if we have a local settings.xml file, we copy it.
    if [[ -f "${HOME}/.m2/settings.xml" ]]; then
      cp -p "${HOME}/.m2/settings.xml" "${MAVEN_LOCAL_REPO}"
    fi
    MAVEN_ARGS=("${MAVEN_ARGS[@]}" "-Dmaven.repo.local=${MAVEN_LOCAL_REPO}")

    # let's do some cleanup while we're here

    find "${MAVEN_CUSTOM_REPOS_DIR}" \
      -name '*-*-*' \
      -type d \
      -mtime +30 \
      -maxdepth 1 \
      -print \
        > "${logfile}"

    while read -r line; do
      echo "Removing old maven repo ${line}"
      rm -rf "${line}"
    done < "${logfile}"
  fi
}

function maven_filefilter
{
  declare filename=$1

  if [[ ${filename} =~ pom\.xml$ ]]; then
    yetus_debug "tests/compile: ${filename}"
    add_test compile
  fi
}

function maven_buildfile
{
  echo "pom.xml"
}

function maven_executor
{
  echo "${MAVEN}" "${MAVEN_ARGS[@]}"
}

function mvnsite_filefilter
{
  local filename=$1

  if [[ ${BUILDTOOL} = maven ]]; then
    if [[ ${filename} =~ src/site ]]; then
      yetus_debug "tests/mvnsite: ${filename}"
      add_test mvnsite
    fi
  fi
}

function maven_modules_worker
{
  declare repostatus=$1
  declare tst=$2

  # shellcheck disable=SC2034
  UNSUPPORTED_TEST=false

  case ${tst} in
    findbugs)
      modules_workers "${repostatus}" findbugs test-compile findbugs:findbugs -DskipTests=true
    ;;
    compile)
      modules_workers "${repostatus}" compile clean test-compile -DskipTests=true
    ;;
    distclean)
      modules_workers "${repostatus}" distclean clean -DskipTests=true
    ;;
    javadoc)
      modules_workers "${repostatus}" javadoc clean javadoc:javadoc -DskipTests=true
    ;;
    scaladoc)
      modules_workers "${repostatus}" scaladoc clean scala:doc -DskipTests=true
    ;;
    unit)
      modules_workers "${repostatus}" unit clean test -fae
    ;;
    *)
      # shellcheck disable=SC2034
      UNSUPPORTED_TEST=true
      if [[ ${repostatus} = patch ]]; then
        add_footer_table "${tst}" "not supported by the ${BUILDTOOL} plugin"
      fi
      yetus_error "WARNING: ${tst} is unsupported by ${BUILDTOOL}"
      return 1
    ;;
  esac
}

function maven_javac_logfilter
{
  declare input=$1
  declare output=$2

  ${GREP} -E '\[(ERROR|WARNING)\] /.*\.java:' "${input}" > "${output}"
}

## @description  Helper for check_patch_javadoc
## @audience     private
## @stability    evolving
## @replaceable  no
## @return       0 on success
## @return       1 on failure
function maven_javadoc_logfilter
{
  declare input=$1
  declare output=$2

  ${GREP} -E '\[(ERROR|WARNING)\] /.*\.java:' "${input}" > "${output}"
}

## @description  handle diffing maven javac errors
## @audience     private
## @stability    evolving
## @replaceable  no
## @param        branchlog
## @param        patchlog
## @return       differences
function maven_javac_calcdiffs
{
  declare orig=$1
  declare new=$2
  declare tmp=${PATCH_DIR}/pl.$$.${RANDOM}
  declare j

  # first, strip :[line
  # this keeps file,column in an attempt to increase
  # accuracy in case of multiple, repeated errors
  # since the column number shouldn't change
  # if the line of code hasn't been touched
  # shellcheck disable=SC2016
  ${SED} -e 's#:\[[0-9]*,#:#' "${orig}" > "${tmp}.branch"
  # shellcheck disable=SC2016
  ${SED} -e 's#:\[[0-9]*,#:#' "${new}" > "${tmp}.patch"

  # compare the errors, generating a string of line
  # numbers. Sorry portability: GNU diff makes this too easy
  ${DIFF} --unchanged-line-format="" \
     --old-line-format="" \
     --new-line-format="%dn " \
     "${tmp}.branch" \
     "${tmp}.patch" > "${tmp}.lined"

  # now, pull out those lines of the raw output
  # shellcheck disable=SC2013
  for j in $(cat "${tmp}.lined"); do
    # shellcheck disable=SC2086
    head -${j} "${new}" | tail -1
  done

  rm "${tmp}.branch" "${tmp}.patch" "${tmp}.lined" 2>/dev/null
}

## @description  handle diffing maven javadoc errors
## @audience     private
## @stability    evolving
## @replaceable  no
## @param        branchlog
## @param        patchlog
## @return       differences
function maven_javadoc_calcdiffs
{
  declare orig=$1
  declare new=$2
  declare tmp=${PATCH_DIR}/pl.$$.${RANDOM}
  declare j

  # can't use the generic handler for this because of the
  # [WARNING], etc headers.
  # strip :linenum from the output, keeping the filename
  # shellcheck disable=SC2016
  ${SED} -e 's#:[0-9]*:#:#' "${orig}" > "${tmp}.branch"
  # shellcheck disable=SC2016
  ${SED} -e 's#:[0-9]*:#:#' "${new}" > "${tmp}.patch"

  # compare the errors, generating a string of line
  # numbers. Sorry portability: GNU diff makes this too easy
  ${DIFF} --unchanged-line-format="" \
     --old-line-format="" \
     --new-line-format="%dn " \
     "${tmp}.branch" \
     "${tmp}.patch" > "${tmp}.lined"

  # now, pull out those lines of the raw output
  # shellcheck disable=SC2013
  for j in $(cat "${tmp}.lined"); do
    # shellcheck disable=SC2086
    head -${j} "${new}" | tail -1
  done

  rm "${tmp}.branch" "${tmp}.patch" "${tmp}.lined" 2>/dev/null
}

function maven_builtin_personality_modules
{
  local repostatus=$1
  local testtype=$2

  local module

  yetus_debug "Using builtin personality_modules"
  yetus_debug "Personality: ${repostatus} ${testtype}"

  clear_personality_queue

  # this always makes sure the local repo has a fresh
  # copy of everything per pom rules.
  if [[ ${repostatus} == branch
     && ${testtype} == mvninstall ]];then
     personality_enqueue_module .
     return
   fi

  for module in ${CHANGED_MODULES}; do
    # shellcheck disable=SC2086
    personality_enqueue_module ${module}
  done
}

function maven_builtin_personality_file_tests
{
  local filename=$1

  yetus_debug "Using builtin mvn personality_file_tests"

  if [[ ${filename} =~ src/main/webapp ]]; then
    yetus_debug "tests/webapp: ${filename}"
  elif [[ ${filename} =~ \.sh
       || ${filename} =~ \.cmd
       || ${filename} =~ src/main/scripts
       || ${filename} =~ src/test/scripts
       ]]; then
    yetus_debug "tests/shell: ${filename}"
  elif [[ ${filename} =~ \.c$
       || ${filename} =~ \.cc$
       || ${filename} =~ \.h$
       || ${filename} =~ \.hh$
       || ${filename} =~ \.proto$
       || ${filename} =~ \.cmake$
       || ${filename} =~ CMakeLists.txt
       ]]; then
    yetus_debug "tests/units: ${filename}"
    add_test cc
    add_test unit
  elif [[ ${filename} =~ \.scala$
       || ${filename} =~ src/scala ]]; then
    add_test scalac
    add_test scaladoc
    add_test unit
  elif [[ ${filename} =~ build.xml$
       || ${filename} =~ pom.xml$
       || ${filename} =~ \.java$
       || ${filename} =~ src/main
       ]]; then
      yetus_debug "tests/javadoc+units: ${filename}"
      add_test javac
      add_test javadoc
      add_test unit
  fi

  if [[ ${filename} =~ src/test ]]; then
    yetus_debug "tests"
    add_test unit
  fi

  if [[ ${filename} =~ \.java$ ]]; then
    add_test findbugs
  fi
}

## @description  Confirm site pre-patch
## @audience     private
## @stability    stable
## @replaceable  no
## @return       0 on success
## @return       1 on failure
function mvnsite_postcompile
{
  declare repostatus=$1
  declare result=0

  if [[ ${BUILDTOOL} != maven ]]; then
    return 0
  fi

  verify_needed_test mvnsite
  if [[ $? == 0 ]];then
    return 0
  fi

  if [[ "${repostatus}" = branch ]]; then
    big_console_header "Pre-patch ${PATCH_BRANCH} maven site verification"
  else
    big_console_header "Patch maven site verification"
  fi


  personality_modules "${repostatus}" mvnsite
  modules_workers "${repostatus}" mvnsite clean site site:stage
  result=$?
  modules_messages "${repostatus}" mvnsite true
  if [[ ${result} != 0 ]]; then
    return 1
  fi
  return 0
}

## @description  Make sure Maven's eclipse generation works.
## @audience     private
## @stability    evolving
## @replaceable  no
## @return       0 on success
## @return       1 on failure
function mvneclipse_postcompile
{
  declare repostatus=$1
  declare result=0

  if [[ ${BUILDTOOL} != maven ]]; then
    return 0
  fi

  verify_needed_test javac
  if [[ $? == 0 ]]; then
    return 0
  fi

  if [[ "${repostatus}" = branch ]]; then
    big_console_header "Pre-patch ${PATCH_BRANCH} maven eclipse verification"
  else
    big_console_header "Patch maven eclipse verification"
  fi

  personality_modules "${repostatus}" mvneclipse
  modules_workers "${repostatus}" mvneclipse eclipse:clean eclipse:eclipse
  result=$?
  modules_messages "${repostatus}" mvneclipse true
  if [[ ${result} != 0 ]]; then
    return 1
  fi
  return 0
}

## @description  Verify mvn install works
## @audience     private
## @stability    evolving
## @replaceable  no
## @return       0 on success
## @return       1 on failure
function maven_precompile
{
  declare repostatus=$1
  declare result=0

  if [[ ${BUILDTOOL} != maven ]]; then
    return 0
  fi

  verify_needed_test javadoc
  result=$?

  verify_needed_test javac
  ((result = result + $? ))
  if [[ ${result} == 0 ]]; then
    return 0
  fi

  if [[ "${repostatus}" = branch ]]; then
    big_console_header "Pre-patch ${PATCH_BRANCH} maven install"
  else
    big_console_header "Patch maven install"
  fi

  personality_modules "${repostatus}" mvninstall
  modules_workers "${repostatus}" mvninstall -fae clean install -DskipTests=true -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dfindbugs.skip=true
  result=$?
  modules_messages "${repostatus}" mvninstall true
  if [[ ${result} != 0 ]]; then
    return 1
  fi
  return 0
}

function maven_docker_support
{
  echo "-v ${HOME}/.m2:${HOME}/.m2" > "${PATCH_DIR}/buildtool-docker-params.txt"

  if [[ ${MAVEN_CUSTOM_REPOS} = true ]]; then
    echo "-v ${MAVEN_CUSTOM_REPOS_DIR}:${MAVEN_CUSTOM_REPOS_DIR}" \
      >> "${PATCH_DIR}/buildtool-docker-params.txt"
  fi
}

## @description  worker for maven reordering
## @audience     private
## @stability    evolving
## @replaceable  no
## @param        repostatus
## @param        module
function maven_reorder_module_process
{
  declare repostatus=$1
  declare module=$2
  declare indexd
  declare indexm
  declare deplist
  declare fn
  declare basemod

  yetus_debug "Maven: check order: ${module}"

  # this is a recursive function; no need to process
  # modules that we have already seen
  if [[ " ${MAVEN_ALREADY[@]} " =~ \ ${module}\  ]]; then
    return
  fi

  # immediately place a module in the list to avoid
  # loops
  MAVEN_ALREADY=("${MAVEN_ALREADY[@]}" "${module}")

  pushd "${BASEDIR}/${module}" >/dev/null
  fn=$(module_file_fragment "${module}")

  # get the dependency list from maven
  #shellcheck disable=SC2046
  echo_and_redirect "${PATCH_DIR}/maven-${repostatus}-dependencylist-${fn}.txt" \
    $("${BUILDTOOL}_executor") dependency:list \
      -DoutputFile="${PATCH_DIR}/${repostatus}-mvndeporder-${fn}.txt"

  # if this fails, there's really not much we can do other than tell the
  # user that it did. So we'll press on and just hope for the best

  if [[ $? != 0 ]]; then
    add_vote_table -1 mvndep "${repostatus}'s ${module} dependency:list failed"
    add_footer_table mvndep "${fn}: @@BASE@@/maven-${repostatus}-dependencylist-${fn}.txt"
  fi

  # take the list from maven, and pull out the artifactids. this means
  # we have an assumption that the module names we are given map
  # 1:1 to the artifactid
  deplist=$(cut -f2 -d: "${PATCH_DIR}/${repostatus}-mvndeporder-${fn}.txt")

  # loop through the generated dependency artificatid list
  # and try to match it to any of the other modules we are working on
  # if it is a match, process it.  dependencies that aren't being hit
  # by the patch should be irrelevant since maven will pick them up
  # from the repo caches.  if a dependency really does matter, then
  # the personality will have a chance to manipulate this list later
  for indexd in ${deplist}; do
    for indexm in ${CHANGED_MODULES}; do

      # modules could be foo/bar, where bar is the artifactid
      # so get the basename and compare that too
      basemod=$(basename "${indexm}")
      if [[ " ${indexd} " = " ${indexm} "
         || " ${indexd} " = " ${basemod} " ]]; then
        maven_reorder_module_process "${repostatus}" "${indexm}"
      fi
    done
  done
  popd >/dev/null

  # at this point, any modules that we care about should have been placed
  # before us.  now add the one we've been working on.  if the artificatids
  # don't match, then we're effectively back to the old behavior of
  # using fs globs and the personality will have to do the hard work
  yetus_debug "Maven: placing ${module}"
  MAVEN_NEWLIST=("${MAVEN_NEWLIST[@]}" " ${module} ")
}

## @description  take a stab at reordering modules based upon
## @description  maven dependency order
## @audience     private
## @stability    evolving
## @replaceable  no
## @param        repostatus
## @param        module
function maven_reorder_modules
{
  declare repostatus=$1
  declare index

  # sidenote: this code does not get called when there is only one
  # module, so no reason to shortcut that

  if [[ "${MAVEN_DEPENDENCY_ORDER}" != "true" ]]; then
    return
  fi

  big_console_header "Determining Maven Dependency Order"

  start_clock

  # this will get called again, so always make sure we start fresh
  MAVEN_ALREADY=()
  MAVEN_NEWLIST=()

  yetus_debug "Maven: start re-ordering modules"
  yetus_debug "Starting list: ${CHANGED_MODULES}"

  # sort the list.  parents will likely get us most of the
  # dependency list sooner/more correct, esp if . is in the list
  # shellcheck disable=SC2086
  for index in $(echo ${CHANGED_MODULES} | tr ' ' '\n' |  sort); do
    maven_reorder_module_process "${repostatus}" "${index}"
  done

  CHANGED_MODULES="${MAVEN_NEWLIST[*]}"

  yetus_debug "Maven: finish re-ordering modules"
  yetus_debug "Finished list: ${CHANGED_MODULES}"

  add_vote_table 0 mvndep "Maven dependency ordering for ${repostatus}"
}