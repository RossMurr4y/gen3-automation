#!/usr/bin/env bash

# Utility Functions
#
# This script is designed to be sourced into other scripts

# -- Detect is namedef support available
function namedef_supported() {
  [[ "${BASH_VERSION}" =~ ([^.]+)\.([^.]+)\.(.+) ]] || return 1

  [[ (${BASH_REMATCH[1]} -gt 4) || (${BASH_REMATCH[2]} -ge 3) ]]
}

# -- Error handling  --

export LOG_LEVEL_DEBUG="debug"
export LOG_LEVEL_TRACE="trace"
export LOG_LEVEL_INFORMATION="info"
export LOG_LEVEL_WARNING="warn"
export LOG_LEVEL_ERROR="error"
export LOG_LEVEL_FATAL="fatal"

declare -A LOG_LEVEL_ORDER
LOG_LEVEL_ORDER=(
  ["${LOG_LEVEL_DEBUG}"]="0"
  ["${LOG_LEVEL_TRACE}"]="1"
  ["${LOG_LEVEL_INFORMATION}"]="3"
  ["${LOG_LEVEL_WARNING}"]="5"
  ["${LOG_LEVEL_ERROR}"]="7"
  ["${LOG_LEVEL_FATAL}"]="9"
)

function checkLogLevel() {
  local level="$1"

  [[ (-n "${level}") && (-n "${LOG_LEVEL_ORDER[${level}]}") ]] && { echo -n "${level}"; return 0; }
  [[ -n "${GENERATION_DEBUG}" ]] && { echo -n "${LOG_LEVEL_DEBUG}"; return 0; }
  echo -n "${LOG_LEVEL_INFORMATION}"
  return 0
}

# Default implementation - can be overriden by caller
function getLogLevel() {
  checkLogLevel
}

# Default implementation - can be overriden by caller but must honour parameter order
function outputLogEntry() {
  local severity="${1^}"; shift
  local parts=("$@")

  echo -e "\n(${severity})" "${parts[@]}"
  return 0
}

function willLog() {
  local severity="$1"

  [[ ${LOG_LEVEL_ORDER[$(getLogLevel)]} -le ${LOG_LEVEL_ORDER[${severity}]} ]]
}

function message() {
  local severity="$1"; shift
  local parts=("$@")

  if willLog "${severity}"; then
    outputLogEntry "${severity}" "${parts[@]}"
  else
    return 0
  fi
}

function locationMessage() {
  local restore_nullglob=$(shopt -p nullglob)
  local restore_globstar=$(shopt -p globstar)
  shopt -u nullglob globstar

  echo -n "$@" "Are we in the right place?"

  ${restore_nullglob}
  ${restore_globstar}
}

function cantProceedMessage() {
  echo -n "$@" "Nothing to do."
}

function debug() {
  message "${LOG_LEVEL_DEBUG}" "$@"
}

function trace() {
  message "${LOG_LEVEL_TRACE}" "$@"
}

function info() {
  message "${LOG_LEVEL_INFORMATION}" "$@"
}

function warning() {
  message "${LOG_LEVEL_WARNING}" "$@"
}

function error() {
  message "${LOG_LEVEL_ERROR}" "$@" >&2
}

function fatal() {
  message "${LOG_LEVEL_FATAL}" "$@" >&2
}

function fatalOption() {
  local option="${1:-${OPTARG}}"

  fatal "Invalid option: \"-${option}\""
}

function fatalOptionArgument() {
  local option="${1:-${OPTARG}}"

  fatal "Option \"-${option}\" requires an argument"
}

function fatalCantProceed() {
  fatal "$(cantProceedMessage "$@")"
}

function fatalLocation() {
  local restore_nullglob=$(shopt -p nullglob)
  local restore_globstar=$(shopt -p globstar)
  shopt -u nullglob globstar

  fatal "$(locationMessage "$@")"

  ${restore_nullglob}
  ${restore_globstar}
}

function fatalDirectory() {
  local name="$1"; shift

  fatalLocation "We don\'t appear to be in the ${name} directory."
}

function fatalMandatory() {
  fatal "Mandatory arguments missing. Check usage via -h option."
}

# -- String manipulation --

function join() {
  local IFS="$1"; shift
  echo -n "$*"
}

function contains() {
  local string="$1"; shift
  local pattern="$1"; shift

  [[ "${string}" =~ ${pattern} ]]
}

function generateComplexString() {
  # String suitable for a password - Alphanumeric and special characters
  local length="$1"; shift

  echo "$(dd bs=256 count=1 if=/dev/urandom | base64 | env LC_CTYPE=C tr -dc '[:punct:][:alnum:]' | tr -d '@"/+'  | fold -w "${length}" | head -n 1)" || return $?
}

function generateSimpleString() {
  # Simple string - Alphanumeric only
  local length="$1"; shift

  echo "$(dd bs=256 count=1 if=/dev/urandom | base64 | env LC_CTYPE=C tr -dc '[:alnum:]' | fold -w "${length}" | head -n 1)" || return $?
}

# -- File manipulation --

function formatPath() {
  join "/" "$@"
}

function filePath() {
  local file="$1"; shift

  contains "${file}" "/" &&
    echo -n "${file%/*}" ||
    echo -n ""
}

function fileName() {
  local file="$1"; shift

  echo -n "${file##*/}"
}

function fileBase() {
  local file="$1"; shift

  local name="$(fileName "${file}")"
  echo -n "${name%.*}"
}

function fileExtension() {
  local file="$1"; shift

  local name="$(fileName "${file}")"
  echo -n "${name##*.}"
}

function fileContents() {
  local file="$1"; shift

  [[ -f "${file}" ]] && cat "${file}"
}

function fileContentsInEnv() {
  local env="$1"; shift
  local files=("$@"); shift

  for file in "${files[@]}"; do
    if [[ -f "${file}" ]]; then
      declare -gx ${env}="$(fileContents "${file}")"
      break
    fi
  done
}

function findAncestorDir() {
  local ancestor="$1"; shift
  local current="${1:-$(pwd)}"

  while [[ -n "${current}" ]]; do
    # Ancestor can either be a directory or a marker file
    if [[ ("$(fileName "${current}")" == "${ancestor}") ||
            ( -f "${current}/${ancestor}" ) ]]; then
      echo -n "${current}"
      return 0
    fi
    current="$(filePath "${current}")"
  done

  return 1
}

function findDir() {
  local root_dir="$1"; shift
  local patterns=("$@")

  local restore_nullglob="$(shopt -p nullglob)"
  local restore_globstar="$(shopt -p globstar)"
  shopt -s nullglob globstar

  local matches=()
  for pattern in "${patterns[@]}"; do
    matches+=("${root_dir}"/**/${pattern})
  done

  ${restore_nullglob}
  ${restore_globstar}

  for match in "${matches[@]}"; do
    [[ -f "${match}" ]] && echo -n "$(filePath "${match}")" && return 0
    [[ -d "${match}" ]] && echo -n "${match}" && return 0
  done

  return 1
}

function findFile() {

  local restore_nullglob="$(shopt -p nullglob)"
  local restore_globstar="$(shopt -p globstar)"
  shopt -s nullglob globstar

  # Note that any spaces in file specs must be escaped
  local matches=($@)

  ${restore_nullglob}
  ${restore_globstar}

  for match in "${matches[@]}"; do
    [[ -f "${match}" ]] && echo -n "${match}" && return 0
  done

  return 1
}

function findFiles() {

  local restore_nullglob="$(shopt -p nullglob)"
  local restore_globstar="$(shopt -p globstar)"
  shopt -s nullglob globstar

  # Note that any spaces in file specs must be escaped
  local matches=($@)

  ${restore_nullglob}
  ${restore_globstar}

  local file_match="false"

  for match in "${matches[@]}"; do
    if [[ -f "${match}" ]]; then
      echo "${match}"
      local file_match="true"
    fi
  done

  if [[ "${file_match}" == "true" ]]; then
    return 0
  fi

  return 1
}

# -- Array manipulation --

function inArray() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    eval "local array=(\"\${${array_name}[@]}\")"
  fi
  local pattern="$1"

  contains "${array[*]}" "${pattern}"
}

function arrayFromList() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    local array=()
  fi
  local list="$1"; shift
  local separators="${1:- ,}"

  # Handle situation of multi-line inputs e.g. from Jenkins multi-line string parameter plugin
  readarray -t list_lines <<< "${list}"

  IFS="${separators}" read -ra array <<< "$(join "${separators:0:1}" "${list_lines[@]}" )"
  if ! namedef_supported; then
    eval "${array_name}=(\"\${array[@]}\")"
  fi
}

function arrayFromCommand() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    local array=()
  fi
  local command="$1"; shift

  readarray -t array < <(${command})
  if ! namedef_supported; then
    eval "${array_name}=(\"\${array[@]}\")"
  fi
}

function listFromArray() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    eval "local array=(\"\${${array_name}[@]}\")"
  fi

  local separators="${1:- ,}"

  join "${separators}" "${array[@]}"
}

function arraySize() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    eval "local array=(\"\${${array_name}[@]}\")"
  fi

  echo -n "${#array[@]}"
}

function arrayIsEmpty() {
  local array="$1";

  [[ $(arraySize "${array}") -eq 0 ]]
}

function reverseArray() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    eval "local array=(\"\${${array_name}[@]}\")"
  fi
  local target="$1"; shift

  if [[ -n "${target}" ]]; then
    if namedef_supported; then
      local -n result="${target}"
    else
      local result=()
    fi
  else
    local result=()
  fi

  result=()
  for (( index=${#array[@]}-1 ; index>=0 ; index-- )) ; do
    result+=("${array[index]}")
  done

  if [[ (-n "${target}") ]]; then
    if ! namedef_supported; then
      eval "${target}=(\"\${result[@]}\")"
    fi
  else
    if namedef_supported; then
      array=("${result[@]}")
    else
      eval "${array_name}=(\"\${result[@]}\")"
    fi
  fi
}

function addToArrayInternal() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    eval "local array=(\"\${${array_name}[@]}\")"
  fi
  local type="$1"; shift
  local prefix="$1"; shift
  local elements=("$@")

  for element in "${elements[@]}"; do
    if [[ -n "${element}" ]]; then
      [[ "${type,,}" == "stack" ]] &&
        array=("${prefix}${element}" "${array[@]}") ||
        array+=("${prefix}${element}")
    fi
  done

  ! namedef_supported && eval "${array_name}=(\"\${array[@]}\")"
  return 0
}

function removeFromArrayInternal() {
  if namedef_supported; then
    local -n array="$1"; shift
  else
    local array_name="$1"; shift
    eval "local array=(\"\${${array_name}[@]}\")"
  fi
  local type="$1"; shift
  local count="${1:-1}"; shift

  local remaining=$(( ${#array[@]} - ${count} ))
  [[ ${remaining} -lt 0 ]] && remaining=0

  [[ "${type,,}" == "stack" ]] &&
    array=("${array[@]:${count}}") ||
    array=("${array[@]:0:${remaining}}")

  ! namedef_supported && eval "${array_name}=(\"\${array[@]}\")"
  return 0
}

function addToArray() {
  local array="$1"; shift
  local elements=("$@")

  addToArrayInternal "${array}" "array" "" "${elements[@]}"
}

function addToArrayHead() {
  local array="$1"; shift
  local elements=("$@")

  addToArrayInternal "${array}" "stack" "" "${elements[@]}"
}

function removeFromArray() {
  local array="$1"; shift
  local count="$1"; shift

  removeFromArrayInternal "${array}" "array" "${count}"
}

function removeFromArrayHead() {
  local array="$1"; shift
  local count="$1"; shift

  removeFromArrayInternal "${array}" "stack" "${count}"
}

function pushStack() {
  local array="$1"; shift
  local elements=("$@")

  addToArrayHead "${array}" "${elements[@]}"
}

function popStack() {
  local array="$1"; shift
  local count="$1"; shift

  removeFromArrayHead "${array}" "${count}"
}

# -- Temporary file management --

# OS Temporary directory
function getOSTempRootDir() {
  uname | grep -iq "MINGW64" &&
    echo -n "c:/tmp" ||
    echo -n "$(filePath $(mktemp -u -t tmp.XXXXXXXXXX))"
}

# Default implementation - can be overriden by caller
function getTempRootDir() {
  getOSTempRootDir
}

function getTempDir() {
  local template="$1"; shift
  local tmp_dir="$1"; shift

  [[ -z "${template}" ]] && template="XXXXXX"
  [[ -z "${tmp_dir}" ]] && tmp_dir="$(getTempRootDir)"

  [[ -n "${tmp_dir}" ]] &&
    mktemp -d "${tmp_dir}/${template}" ||
    mktemp -d "$(getOSTempRootDir)/${template}"
}

export tmp_dir_stack=()

function pushTempDir() {
  local template="$1"; shift

  local tmp_dir="$( getTempDir "${template}" "${tmp_dir_stack[0]}" )"

  pushStack "tmp_dir_stack" "${tmp_dir}"
}

function popTempDir() {
  local count="${1:-1}"; shift

  # Popped value not returned but keep the code here for now
  local index=$(( $count - 1 ))
  local tmp_dir="${tmp_dir_stack[@]:${index}:1}"

  popStack "tmp_dir_stack" "${count}"
}

function getTopTempDir() {
  echo -n "${tmp_dir_stack[@]:0:1}"
}

function getTempFile() {
  local template="$1"; shift
  local tmp_dir="$1"; shift

  [[ -z "${template}" ]] && template="XXXXXX"
  [[ -z "${tmp_dir}" ]] && tmp_dir="$(getTempRootDir)"

  [[ -n "${tmp_dir}" ]] &&
    mktemp    "${tmp_dir}/${template}" ||
    mktemp -t "${template}"
}

# -- Cli file generation --

function split_cli_file() {
  local cli_file="$1"; shift
  local outdir="$1"; shift

  for resource in $( jq -r 'keys[]' <"${cli_file}" ) ; do
    for command in $( jq -r ".$resource | keys[]"<"${cli_file}" ); do
        jq ".${resource}.${command}" >"${outdir}/cli-${resource}-${command}.json" <"${cli_file}"
    done
  done
}

# -- JSON manipulation --

function runJQ() {
  local arguments=("$@")

  # TODO(mfl): remove once path length limitations in jq are fixed

  local file_seen="false"
  local file
  local tmp_dir="."
  local modified_arguments=()
  local return_status

  for argument in "${arguments[@]}"; do
    if [[ -f "${argument}" ]]; then
      if [[ "${file_seen}" != "true" ]]; then
        pushTempDir "${FUNCNAME[0]}_XXXXXX"
        tmp_dir="$(getTopTempDir)"
        file_seen="true"
      fi
      file="$( getTempFile "XXXXXX" "${tmp_dir}" )"
      cp "${argument}" "${file}" > /dev/null
      modified_arguments+=("./$(fileName "${file}" )")
    else
      modified_arguments+=("${argument}")
    fi
  done

  # TODO(mfl): Add -L once path length limitations fixed
  (cd ${tmp_dir}; jq "${modified_arguments[@]}"); return_status=$?
  [[ "${file_seen}" == "true" ]] && popTempDir
  return ${return_status}
}

function jqMergeFilter() {
  local files=("$@")

  local command_line=""
  local index=0

  for f in "${files[@]}"; do
    [[ "${index}" > 0 ]] && command_line+=" * "
    command_line+=".[${index}]"
    index=$(( $index + 1 ))
  done

  echo -n "${command_line}"
}

function jqMerge() {
  local files=("$@")

  if [[ "${#files[@]}" -gt 0 ]]; then
    runJQ -s "$( jqMergeFilter "${files[@]}" )" "${files[@]}"
  else
    echo -n "{}"
    return 0
  fi
}

function getJSONValue() {
  local file="$1"; shift
  local patterns=("$@")

  local value=""

  for pattern in "${patterns[@]}"; do
    value="$(runJQ -r "${pattern} | select (.!=null)" < "${file}")"
    [[ -n "${value}" ]] && echo -n "${value}" && return 0
  done

  return 1
}

function addJSONAncestorObjects() {
  local file="$1"; shift
  local ancestors=("$@")

  # Reverse the order of the ancestors
  local pattern="."

  for (( index=${#ancestors[@]}-1 ; index >= 0 ; index-- )) ; do
    [[ -n "${ancestors[index]}" ]] && pattern="{\"${ancestors[index]}\" : ${pattern} }"
  done

  runJQ "${pattern}" < "${file}"
}

# -- KMS --

function decrypt_kms_string() {
  local region="$1"; shift
  local value="$1"; shift

  local tmp_file="$(getTempFile)"
  local return_status

  echo "${value}" | base64 --decode > "${tmp_file}"
  aws --region "${region}" kms decrypt --ciphertext-blob "fileb://${tmp_file}" --output text --query Plaintext | base64 --decode; return_status=$?

  rm ${tmp_file}
  return ${return_status}
}

function encrypt_kms_string() {
  local region="$1"; shift
  local value="$1"; shift
  local kms_key_id="$1"; shift

  aws --region "${region}" kms encrypt --key-id "${kms_key_id}" --plaintext "${value}" --query CiphertextBlob --output text
}

# -- IAM --

function create_iam_accesskey() {
  local region="$1"; shift
  local username="$1"; shift

  accesskey="$(aws --region "${region}" iam create-access-key --user-name "${username}" )" || return $?

  if [[ -n "${accesskey}" ]]; then
    access_key_id="$( echo "${accesskey}" | jq -r '.AccessKey.AccessKeyId')"
    secret_access_key="$( echo "${accesskey}" | jq -r '.AccessKey.SecretAccessKey')"

    echo "${access_key_id} ${secret_access_key}"
    return 0

  else
    fatal "Could not generate accesskey for ${username}"
    return 255
  fi
}

function get_iam_smtp_password() {
  local secretkey="$1"; shift

  (echo -en "\x02"; echo -n 'SendRawEmail' \
  | openssl dgst -sha256 -hmac $secretkey -binary) \
  | openssl enc -base64
}

function manage_iam_userpassword() {
  local region="$1"; shift
  local action="$1"; shift
  local username="$1"; shift
  local password="$1"; shift

  login_profile="$(aws --region "${region}" iam get-login-profile --user-name "${username}" --query 'LoginProfile.UserName' --output text 2>/dev/null )"

  if [[ "${action}" == "delete" && "${login_profile}" == "${username}" ]]; then
    aws --region "${region}" iam delete-login-profile --user-name "${username}" || return $?
  elif [[ "${login_profile}" != "${username}" ]]; then
    aws --region "${region}" iam create-login-profile --user-name "${username}" --password "${password}" --no-password-reset-required || return $?
  else
    aws --region "${region}" iam update-login-profile --user-name "${username}" --password "${password}" --no-password-reset-required || return $?
  fi
}

# -- Cognito --

function update_cognito_userpool() {
  local region="$1"; shift
  local userpoolid="$1"; shift
  local configfile="$1"; shift

  aws --region "${region}" cognito-idp update-user-pool --user-pool-id "${userpoolid}" --cli-input-json "file://${configfile}"
}

function update_userpool_client() {
  local region="$1"; shift
  local userpoolid="$1"; shift
  local userpoolclientid="$1"; shift
  local configfile="$1"; shift

  aws --region "${region}" cognito-idp update-user-pool-client --user-pool-id "${userpoolid}" --client-id "${userpoolclientid}" --cli-input-json "file://${configfile}"
}

function manage_congnito_domain() {
  local region="$1"; shift
  local userpoolid="$1"; shift
  local configfile="$1"; shift
  local action="$1"; shift

  local return_status=0

  domain="$( jq -r '.Domain' < $configfile )"
  domain_userpool="$( aws --region ${region} cognito-idp describe-user-pool-domain --domain ${domain} | jq -r '.DomainDescription.UserPoolId | select (.!=null)' )"

  if [[ -z "${domain_userpool}" ]]; then

    case "${action}" in
        create)
            info "Adding domain to userpool"
            aws --region "${region}" cognito-idp create-user-pool-domain --user-pool-id "${userpoolid}" --cli-input-json "file://${configfile}" || return $?
            return_status=$?
            ;;
        delete)
            info "Domain not assigned to a userpool. Nothing to do"
            ;;
    esac

  elif [[ "${domain_userpool}" != "${userpoolid}" ]]; then
    error "User Pool Domain ${domain} is used by userpool ${domain_userpool}"
    return_status=255

  else
    case "${action}" in
        create)
            info "User Pool domain already configured"
            ;;
        delete)
            info "Deleting domain from user pool"
            aws --region "${region}" cognito-idp delete-user-pool-domain --user-pool-id "${userpoolid}" --domain "${domain}" || return $?
            ;;
    esac
  fi

  return ${return_status}
}

# -- Data Pipeline --

function create_data_pipeline() {
  local region="$1"; shift
  local configfile="$1"; shift

  pipeline="$(aws --region "${region}" datapipeline create-pipeline --cli-input-json "file://${configfile}" || return $?)"
  if [[ -n "${pipeline}" ]]; then
    echo "${pipeline}" | jq -r '.pipelineId | select (.!=null)'
    return 0

  else
    fatal "Could not create pipeline"
    return 255
  fi
}

function update_data_pipeline() {
  local region="$1"; shift
  local pipelineid="$1"; shift
  local definitionfile="$1"; shift
  local parameterobjectfile="$1"; shift
  local parametervaluefile="$1"; shift

  pipeline_details="$(aws --region "${region}" datapipeline put-pipeline-definition --pipeline-id "${pipelineid}" --pipeline-definition "file://${definitionfile}" --parameter-objects "file://${parameterobjectfile}" --parameter-values-uri "file://${parametervaluefile}" )"
  pipeline_errored="$(echo "${pipeline_details}" | jq -r '.errored ')"

  if [[ "${pipeline_errored}" == "false" ]]; then
    info "Pipeline definition update successful"
    info "${pipeline_details}"
    return 0
  else
    fatal "Pipeline definition did not work as expected"
    fatal "${pipeline_details}"
    return 255
  fi
}

# -- ElasticSearch --

function update_es_domain() {
  local region="$1"; shift
  local esid="$1"; shift
  local configfile="$1"; shift

  aws --region "${region}" es update-elasticsearch-domain-config --domain-name "${esid}" --cli-input-json "file://${configfile}" || return $?
}

# -- Elastic Load Balancing --

function create_elbv2_rule() {
  local region="$1"; shift
  local listenerid="$1"; shift
  local configfile="$1"; shift

  rule_arn="$(aws --region "${region}" elbv2 create-rule --listener-arn "${listenerid}" --cli-input-json "file://${configfile}" --query 'Rules[0].RuleArn' --output text || return $? )"

  if [[ "${rule_arn}" == "None" ]]; then
    fatal "Rule was not created"
    return 255
  else
    echo "${rule_arn}"
    return 0
  fi
}

function cleanup_elbv2_rules() {
  local region="$1"; shift
  local listenerarn="$1"; shift

  pushTempDir "elbv2_listener_cleanup_XXXXXX"
  local tmp_file="$(getTopTempDir)/cleanup.sh"

  all_listener_rules="$(aws --region "${region}" elbv2 describe-rules --listener-arn "${listenerarn}" --query 'Rules[?!IsDefault].RuleArn' --output json )"

  info "Removing all listener rules from ${listenerarn}"
  if [[ -n "${all_listener_rules}" ]]; then
    echo "${all_listener_rules}" | jq --arg region "${region}" -r '.[] | "aws --region \($region) elbv2 delete-rule --rule-arn \(.) || { status=$?; popTempDir; return $status; }"' > "${tmp_file}"
    if [[ -f "${tmp_file}" ]]; then
      chmod u+x "${tmp_file}"
      "${tmp_file}"
    fi
  fi

  popTempDir
  return 0
}

# -- S3 --

function isBucketAccessible() {
  local region="$1"; shift
  local bucket="$1"; shift
  local prefix="$1"; shift

  local result_file="$(getTopTempDir)/is_bucket_accessible_XXXXXX.txt"

  aws --region ${region} s3 ls "s3://${bucket}/${prefix}${prefix:+/}" > "${result_file}"
}

function copyFilesFromBucket() {
  local region="$1"; shift
  local bucket="$1"; shift
  local prefix="$1"; shift
  local dir="$1"; shift
  local optional_arguments=("$@")

  aws --region ${region} s3 cp --recursive "${optional_arguments[@]}" "s3://${bucket}/${prefix}${prefix:+/}" "${dir}/"
}

function syncFilesToBucket() {
  local region="$1"; shift
  local bucket="$1"; shift
  local prefix="$1"; shift
  if namedef_supported; then
    local -n syncFiles="$1"; shift
  else
    eval "local syncFiles=(\"\${${1}[@]}\")"; shift
  fi
  local optional_arguments=("$@")

  pushTempDir "${FUNCNAME[0]}_XXXXXX"
  local tmp_dir="$(getTopTempDir)"
  local return_status

  # Copy files locally so we can synch with S3, potentially including deletes
  for file in "${syncFiles[@]}" ; do
    if [[ -f "${file}" ]]; then
      case "$(fileExtension "${file}")" in
        zip)
          # Always use local time to force redeploy of files
          # in case we are reverting to an earlier version
          unzip -DD "${file}" -d "${tmp_dir}"
          ;;
        *)
          cp "${file}" "${tmp_dir}"
          ;;
      esac
    fi
  done

  # Now synch with s3
  aws --region ${region} s3 sync "${optional_arguments[@]}" "${tmp_dir}/" "s3://${bucket}/${prefix}${prefix:+/}"; return_status=$?

  popTempDir
  return ${return_status}
}

function deleteTreeFromBucket() {
  local region="$1"; shift
  local bucket="$1"; shift
  local prefix="$1"; shift
  local optional_arguments=("$@")

  # Delete everything below the prefix
  aws --region "${region}" s3 rm "${optional_arguments[@]}" --recursive "s3://${bucket}/${prefix}${prefix:+/}"
}

function deleteBucket() {
  local region="$1"; shift
  local bucket="$1"; shift
  local optional_arguments=("$@")

  # Delete the bucket
  aws --region "${region}" s3 rb "${optional_arguments[@]}" "s3://${bucket}" --force
}

# -- SNS --

function deploy_sns_platformapp() {
  local region="$1"; shift
  local name="$1"; shift
  local existing_arn="$1"; shift
  local encryption_scheme="$1"; shift
  local engine="$1"; shift
  local configfile="$1"; shift

  platform_principal="$(jq -rc '.Attributes.PlatformPrincipal | select (.!=null)' < "${configfile}" )"
  platform_credential="$(jq -rc '.Attributes.PlatformCredential | select (.!=null)' < "${configfile}" )"

  #Decrypt the principal and certificate if they are encrypted
  if [[ "${platform_principal}" == "${encryption_scheme}"* ]]; then
      decrypted_platform_principal="$( decrypt_kms_string "${region}" "${platform_principal#${encryption_scheme}}" || return $? )"
  else
      decrypted_platform_principal="${platform_principal}"
  fi

  if [[ "${platform_credential}" == "${encryption_scheme}"* ]]; then
    decrypted_platform_credential="$( decrypt_kms_string "${region}" "${platform_credential#${encryption_scheme}}" || return $? )"
  else
    decrypted_platform_credential="${platform_credential}"
  fi

  jq -rc '. | del(.Attributes.PlatformPrincipal) | del(.Attributes.PlatformCredential)' < "${configfile}" > "${configfile}_decrypted"

  if [[ -n "${existing_arn}" ]]; then
    platform_app_arn="${existing_arn}"
    update_platform_app="$(aws --region "${region}" sns set-platform-application-attributes --platform-application-arn "${platform_app_arn}" --attributes PlatformPrincipal="${decrypted_platform_principal}",PlatformCredential="${decrypted_platform_credential}"  || return $? )"
  else
    platform_app_arn="$(aws --region "${region}" sns create-platform-application --name "${name}" \
      --attributes PlatformPrincipal="${decrypted_platform_principal}",PlatformCredential="${decrypted_platform_credential}" \
      --platform="${engine}" --query .PlatformApplicationArn --output text )"
  fi

  update_platform_app="$(aws --region "${region}" sns set-platform-application-attributes --platform-application-arn "${platform_app_arn}" --cli-input-json "file://${configfile}_decrypted"  || return $? )"

  if [[ -z "${platform_app_arn}" ]]; then
    fatal "Platform app was not deployed"
    return 255
  else
    echo "${platform_app_arn}"
    return 0
  fi

}

function delete_sns_platformapp() {
  local region="$1"; shift
  local arn="$1"; shift

  aws --region "${region}" sns delete-platform-application --platform-application-arn "${arn}" || return $?
}

function cleanup_sns_platformapps() {
  local region="$1"; shift
  local mobile_notifier_name="$1"; shift
  local expected_platform_arns="$1"; shift

  pushTempDir "${mobile_notifier_name}_cleanup_XXXXXX"
  local tmp_file="$(getTopTempDir)/cleanup.sh"

  all_platform_apps="$(aws --region "${region}" sns list-platform-applications )"
  current_platform_arns="$(echo "${all_platform_apps}" | jq --arg namefilter "${mobile_notifier_name}" -rc '.PlatformApplications[] | select( .PlatformApplicationArn | endswith("/" + $namefilter)) | [ .PlatformApplicationArn ]')"

  if [[ -n "${current_platform_arns}" ]]; then
    unexpected_platform_arns="$(echo "${expected_platform_arns}" | jq --argjson currentarns "${current_platform_arns}" '. - $currentarns')"
    info "Found the following unexpected Platforms: ${unexpected_platform_arns}"
    echo "${unexpected_platform_arns}" | jq --arg region "${region}" -r '.[] | "delete_sns_platform \($region) \(.)"' > "${tmp_file}"

    if [[ -f "${tmp_file}" ]]; then
      chmod u+x "${tmp_file}"
      "${tmp_file}"
    fi
  fi

  popTempDir
  return $?
}

function update_sms_account_attributes() {
  local region="$1"; shift
  local configfile="$1"; shift

  aws --region "${region}" sns set-sms-attributes --cli-input-json "file://${configfile}" || return $?
}

# -- PKI --

function create_pki_credentials() {
  local dir="$1"; shift
  local region="$1"; shift
  local account="$1"; shift

  if [[ (! -f "${dir}/aws-ssh-crt.pem") &&
        (! -f "${dir}/aws-ssh-prv.pem") &&
        (! -f "${dir}/.aws-ssh-crt.pem") &&
        (! -f "${dir}/.aws-ssh-prv.pem") &&
        (! -f "${dir}/.aws-${account}-${region}-ssh-crt.pem") &&
        (! -f "${dir}/.aws-${account}-${region}-ssh-prv.pem") ]]; then
      openssl genrsa -out "${dir}/.aws-${account}-${region}-ssh-prv.pem.plaintext" 2048 || return $?
      openssl rsa -in "${dir}/.aws-${account}-${region}-ssh-prv.pem.plaintext" -pubout > "${dir}/.aws-${account}-${region}-ssh-crt.pem" || return $?
  fi

  if [[ ! -f "${dir}/.gitignore" ]]; then
    cat << EOF > "${dir}/.gitignore"
*.plaintext
*.decrypted
*.ppk
EOF
  fi

  return 0
}

function delete_pki_credentials() {
  local dir="$1"; shift
  local region="$1"; shift
  local account="$1"; shift

  local restore_nullglob="$(shopt -p nullglob)"
  shopt -s nullglob

  rm -f "${dir}"/.aws-${account}-${region}-ssh-crt* "${dir}"/.aws-${account}-${region}-ssh-prv*

  ${restore_nullglob}
}

# -- SSH --

function check_ssh_credentials() {
  local region="$1"; shift
  local name="$1"; shift

  aws --region "${region}" ec2 describe-key-pairs --key-name "${name}" > /dev/null 2>&1
}

function show_ssh_credentials() {
  local region="$1"; shift
  local name="$1"; shift

  aws --region "${region}" ec2 describe-key-pairs --key-name "${name}"
}

function update_ssh_credentials() {
  local region="$1"; shift
  local name="$1"; shift
  local crt_file="$1"; shift

  local crt_content=$(dos2unix < "${crt_file}" | awk 'BEGIN {RS="\n"} /^[^-]/ {printf $1}')
  aws --region "${region}" ec2 import-key-pair --key-name "${name}" --public-key-material "${crt_content}"
}

function delete_ssh_credentials() {
  local region="$1"; shift
  local name="$1"; shift

  aws --region "${region}" ec2 describe-key-pairs --key-name "${name}" > /dev/null 2>&1 && \
    { aws --region "${region}" ec2 delete-key-pair --key-name "${name}" || return $?; }

  return 0
}

# -- SSM --

function update_ssm_document() {
  local region="$1"; shift
  local name="$1"; shift
  local version="$1"; shift
  local contentfile="$1"; shift

  local currentHash="$(aws ssm describe-document --region "${region}" --name "${name}" --document-version "${version}" --query 'Document.Hash' --output text || return $?)"
  local newHash="$(shasum -a 256 ${contentfile} | cut -d " " -f 1 || return $?)"

  if [[ "${currentHash}" != "${newHash}" ]]; then
    aws ssm update-document --region "${region}" --name "${name}" --document-version "${version}" --content "file://${contentfile}" || return $?
  else
    info "No changes required"
  fi

  return $?
}

# -- OAI --

function update_oai_credentials() {
  local region="$1"; shift
  local name="$1"; shift
  local result_file="${1:-$( getTempFile update_oai_XXXXXX.json)}"; shift

  local oai_list_file="$( getTempFile oai_list_XXXXXX.json)"
  local oai_id=

  # Check for existing identity
  aws --region "${region}" cloudfront list-cloud-front-origin-access-identities > "${oai_list_file}" || return $?
  jq ".CloudFrontOriginAccessIdentityList.Items[] | select(.Comment==\"${name}\")" < "${oai_list_file}" > "${result_file}" || return $?
  oai_id=$(jq -r ".Id" < "${result_file}") || return $?

  # Create if not there already
  if [[ -z "${oai_id}" ]]; then
    set -o pipefail
    aws --region "${region}" cloudfront create-cloud-front-origin-access-identity \
      --cloud-front-origin-access-identity-config "{\"Comment\" : \"${name}\", \"CallerReference\" : \"${name}\"}" | jq ".CloudFrontOriginAccessIdentity" > "${result_file}" || return $?
    set +o pipefail
  fi

  # Show the current credential
  cat "${result_file}"

  return 0
}

function delete_oai_credentials() {
  local region="$1"; shift
  local name="$1"; shift

  local oai_delete_file="$( getTempFile oai_delete_XXXXXX.json)"
  local oai_id=
  local oai_etag=

  # Check for existing identity
  aws --region "${region}" cloudfront list-cloud-front-origin-access-identities > "${oai_delete_file}" || return $?
  oai_id=$(jq -r ".CloudFrontOriginAccessIdentityList.Items[] | select(.Comment==\"${name}\") | .Id" < "${oai_delete_file}") || return $?

  # delete if present
  if [[ -n "${oai_id}" ]]; then
    # Retrieve the ETag value
    aws --region "${region}" cloudfront get-cloud-front-origin-access-identity --id "${oai_id}" > "${oai_delete_file}" || return $?
    oai_etag=$(jq -r ".ETag" < "${oai_delete_file}") || return $?
    # Delete the OAI
    aws --region "${region}" cloudfront delete-cloud-front-origin-access-identity --id "${oai_id}" --if-match "${oai_etag}" || return $?
  fi

  return 0
}

# -- RDS --

function add_tag_rds_resource() {
  local region="$1"; shift
  local rds_identifier="$1"; shift
  local key="${1}"; shift
  local value="${1}"; shift

  aws --region "${region}" rds add-tags-to-resource --resource-name "${rds_identifier}" --tags "Key=${key},Value=${value}" || return $?

}

# -- RDS --
function create_snapshot() {
  local region="$1"; shift
  local db_identifier="$1"; shift
  local db_snapshot_identifier="$1"; shift

  # Check that the database exists
  db_info=$(aws --region "${region}" rds describe-db-instances --db-instance-identifier ${db_identifier} )

  if [[ -n "${db_info}" ]]; then
    aws --region "${region}" rds create-db-snapshot --db-snapshot-identifier "${db_snapshot_identifier}" --db-instance-identifier "${db_identifier}" 1> /dev/null || return $?
    
  sleep 2s
  while [ "${exit_status}" != "0" ]
  do
      SNAPSHOT_STATE="$(aws --region "${region}" rds describe-db-snapshots --db-snapshot-identifier "${db_snapshot_identifier}" --query 'DBSnapshots[0].Status' || return $? )" 
      SNAPSHOT_PROGRESS="$(aws --region "${region}" rds describe-db-snapshots --db-snapshot-identifier "${db_snapshot_identifier}" --query 'DBSnapshots[0].PercentProgress' || return $? )"
      info "Snapshot id ${db_snapshot_identifier} creation: state is ${SNAPSHOT_STATE}, ${SNAPSHOT_PROGRESS}%..."

      aws --region "${region}" rds wait db-snapshot-available --db-snapshot-identifier "${db_snapshot_identifier}"
      exit_status="$?"
  done

  db_snapshot=$(aws --region "${region}" rds describe-db-snapshots --db-snapshot-identifier "${db_snapshot_identifier}" || return $?)
  fi
  info "Snapshot Created - $(echo "${db_snapshot}" | jq -r '.DBSnapshots[0] | .DBSnapshotIdentifier + " " + .SnapshotCreateTime' )"
}

function encrypt_snapshot() {
  local region="$1"; shift
  local db_snapshot_identifier="$1"; shift
  local kms_key_id="$1"; shift

  # Check the snapshot status
  snapshot_info=$(aws --region "${region}" rds describe-db-snapshots --db-snapshot-identifier "${db_snapshot_identifier}" || return $? )

  if [[ -n "${snapshot_info}" ]]; then
    if [[ $(echo "${snapshot_info}" | jq -r '.DBSnapshots[0].Status == "Available"') ]]; then

      if [[ $(echo "${snapshot_info}" | jq -r '.DBSnapshots[0].Encrypted') == false ]]; then

        info "Converting snapshot ${db_snapshot_identifier} to an encrypted snapshot"

        # create encrypted snapshot
        aws --region "${region}" rds copy-db-snapshot \
          --source-db-snapshot-identifier "${db_snapshot_identifier}" \
          --target-db-snapshot-identifier "encrypted-${db_snapshot_identifier}" \
          --kms-key-id "${kms_key_id}" 1> /dev/null || return $?

        info "Waiting for temp encrypted snapshot to become available..."
        sleep 2
        aws --region "${region}" rds wait db-snapshot-available --db-snapshot-identifier "encrypted-${db_snapshot_identifier}" || return $?

        info "Removing plaintext snapshot..."
        # delete the original snapshot
        aws --region "${region}" rds delete-db-snapshot --db-snapshot-identifier "${db_snapshot_identifier}"  1> /dev/null || return $?
        aws --region "${region}" rds wait db-snapshot-deleted --db-snapshot-identifier "${db_snapshot_identifier}"  || return $?

        # Copy snapshot back to original identifier
        info "Renaming encrypted snapshot..."
        aws --region "${region}" rds copy-db-snapshot \
          --source-db-snapshot-identifier "encrypted-${db_snapshot_identifier}" \
          --target-db-snapshot-identifier "${db_snapshot_identifier}" 1> /dev/null || return $?

        sleep 2
        aws --region "${region}" rds wait db-snapshot-available --db-snapshot-identifier "${db_snapshot_identifier}"  || return $?

        # Remove the encrypted temp snapshot
        aws --region "${region}" rds delete-db-snapshot --db-snapshot-identifier "encrypted-${db_snapshot_identifier}"  1> /dev/null || return $?
        aws --region "${region}" rds wait db-snapshot-deleted --db-snapshot-identifier "encrypted-${db_snapshot_identifier}"  || return $?

        db_snapshot=$(aws --region "${region}" rds describe-db-snapshots --db-snapshot-identifier "${db_snapshot_identifier}" || return $?)
        info "Snapshot Converted - $(echo "${db_snapshot}" | jq -r '.DBSnapshots[0] | .DBSnapshotIdentifier + " " + .SnapshotCreateTime + " Encrypted: " + (.Encrypted|tostring)' )"

        return 0

      else

        echo "Snapshot ${db_snapshot_identifier} already encrypted"
        return 0

      fi

    else
      echo "Snapshot not in a usuable state $(echo "${snapshot_info}")"
      return 255
    fi
  fi
}

function set_rds_master_password() {
  local region="$1"; shift
  local db_identifier="$1"; shift
  local password="$1"; shift

  info "Resetting master password for RDS instance ${db_identifier}"
  aws --region "${region}" rds modify-db-instance --db-instance-identifier ${db_identifier} --master-user-password "${password}" 1> /dev/null
}

function get_rds_hostname() {
  local region="$1"; shift
  local db_identifier="$1"; shift

  hostname="$(aws --region "${region}" rds describe-db-instances --db-instance-identifier ${db_identifier} --query 'DBInstances[0].Endpoint.Address' --output text)"

  if [[ "${hostname}" != "None" ]]; then
    echo "${hostname}"
    return 0
  else
    fatal "hostname not found for rds instance ${db_identifier}"
    return 255
  fi
}

function check_rds_snapshot_username() {
  local region="$1"; shift
  local db_snapshot_identifier="$1"; shift
  local expected_username="$1"; shift

  info "Checking snapshot username matches expected username"

  snapshot_info="$(aws --region ${region} rds describe-db-snapshots --include-shared --include-public --db-snapshot-identifier ${db_snapshot_identifier} || return $? )"

  if [[ -n "${snapshot_info}" ]]; then
    snapshot_username="$( echo "${snapshot_info}" | jq -r '.DBSnapshots[0].MasterUsername' )"

    if [[ "${snapshot_username}" != "${expected_username}" ]]; then

      error "Snapshot Username does not match the expected username"
      error "Update the RDS username configuration to match the snapshot username"
      error "    Snapshot username: ${snapshot_username}"
      error "    Configured username: ${expected_username}"
      return 128

    else

      info "Snapshot Username is the same as the expected username"
      return 0

    fi
  else

    error "Snapshot ${db_snapshot_identifier} - Not Found"
    return 255

  fi
}

function get_rds_url() {
  local engine="$1"; shift
  local username="$1"; shift
  local password="$1"; shift
  local fqdn="$1"; shift
  local port="$1"; shift
  local database_name="$1"; shift

  echo "${engine}://${username}:${password}@${fqdn}:${port}/${database_name}"
}

# -- Git Repo Management --

function in_git_repo() {
  git status >/dev/null 2>&1
}

function clone_git_repo() {
  local repo_provider="$1"; shift
  local repo_host="$1"; shift
  local repo_path="$1"; shift
  local repo_branch="$1"; shift
  local local_dir="$1";

  [[  (-z "${repo_provider}") ||
      (-z "${repo_host}") ||
      (-z "${repo_path}") ||
      (-z "${repo_branch}") ||
      (-z "${local_dir}") ]] && fatalMandatory && return 1

  local credentials_var="${repo_provider^^}_CREDENTIALS"
  local repo_url="https://${!credentials_var}@${repo_host}/${repo_path}"

  trace "Cloning the ${repo_url} repo and checking out the ${repo_branch} branch ..."

  git clone -b "${repo_branch}" "${repo_url}" "${local_dir}"
  RESULT=$? && [[ ${RESULT} -ne 0 ]] && fatal "Can't clone ${repo_url} repo" && return 1

  return 0
}

function push_git_repo() {
  local repo_url="$1"; shift
  local repo_branch="$1"; shift
  local repo_remote="$1"; shift
  local commit_message="$1"; shift
  local git_user="$1"; shift
  local git_email="$1";

    [[ (-z "${repo_url}") ||
        (-z "${repo_branch}") ||
        (-z "${repo_remote}") ||
        (-z "${commit_message}") ||
        (-z "${git_user}") ||
        (-z "${git_email}") ]] && fatalMandatory && return 1

    git remote show "${repo_remote}" >/dev/null 2>&1
    RESULT=$? && [[ ${RESULT} -ne 0 ]] && fatal "Remote ${repo_remote} is not initialised" && return 1

    # Ensure git knows who we are
    git config user.name  "${git_user}"
    git config user.email "${git_email}"

    # Add anything that has been added/modified/deleted
    git add -A

    if [[ -n "$(git status --porcelain)" ]]; then
        # Commit changes
        trace "Committing to the ${repo_url} repo..."
        git commit -m "${commit_message}"
        RESULT=$? && [[ ${RESULT} -ne 0 ]] && fatal "Can't commit to the ${repo_url} repo" && return 1

        REPO_PUSH_REQUIRED="true"
    fi

    # Update upstream repo
    if [[ "${REPO_PUSH_REQUIRED}" == "true" ]]; then
        trace "Pushing the ${repo_url} repo upstream..."
        git push ${repo_remote} ${repo_branch}
        RESULT=$? && [[ ${RESULT} -ne 0 ]] && \
            fatal "Can't push the ${repo_url} repo changes to upstream repo ${repo_remote}" && return 1
    fi

  return 0
}

function git_mv() {
  in_git_repo && git mv "$@" || mv "$@"
}

function git_rm() {
  in_git_repo && git rm "$@" || rm "$@"
}

# -- semver handling --

# From github.com/fsaintjacques/semver-tool

function semver_validate {
  local version=$1

[[ "$version" =~ ^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\-([^+]+))?(\+(.*))?$ ]] || return 1
  local major=${BASH_REMATCH[1]}
  local minor=${BASH_REMATCH[2]}
  local patch=${BASH_REMATCH[3]}
  local prere=${BASH_REMATCH[5]}
  local build=${BASH_REMATCH[7]}

  echo -n ${major} ${minor} ${patch} ${prere} ${build}
  return 0
}

function semver_compare {
  local v1="$(semver_validate "$1")"; shift
  local v2="$(semver_validate "$1")"; shift

  if [[ (-z "${v1}") || (-z "${v2}") ]]; then
    echo -n "?"
    return 1
  fi

  local v1_components=(${v1})
  local v2_components=(${v2})

  # MAJOR, MINOR and PATCH should compare numericaly
  for i in 0 1 2; do
    local diff=$((${v1_components[$i]} - ${v2_components[$i]}))
    if [[ ${diff} -lt 0 ]]; then
      echo -n -1; return 0
    elif [[ ${diff} -gt 0 ]]; then
      echo -n 1; return 0
    fi
  done

  # PREREL should compare with the ASCII order.
  if [[ -z "${v1_components[3]}" ]] && [[ -n "${v2_components[3]}" ]]; then
    echo -n -1; return 0;
  elif [[ -n "${v1_components[3]}" ]] && [[ -z "${v2_components[3]}" ]]; then
    echo -n 1; return 0;
  elif [[ -n "${v1_components[3]}" ]] && [[ -n "${v2_components[3]}" ]]; then
    if [[ "${v1_components[3]}" > "${v2_components[3]}" ]]; then
      echo -n 1; return 0;
    elif [[ "${v1_components[3]}" < "${v2_components[3]}" ]]; then
      echo -n -1; return 0;
    fi
  fi

  echo -n 0
}

# -- Cloudfront handling --

function invalidate_distribution() {
    local region="$1"; shift
    local distribution_id="$1"; shift

    local paths=("/*")
    [[ -n "$1" ]] && local paths=("$@")

    # Note paths is intentionally not escaped as each token needs to be separately parsed
    aws --region "${region}" cloudfront create-invalidation --distribution-id "${distribution_id}" --paths "${paths[@]}"
}

# -- ENI interface removal  --

function release_enis() {
    local region="$1"; shift
    local requester_id="$1"; shift
    local eni_list_file="$( getTempFile eni_list_XXXXXX.json)"

    aws --region "${region}" ec2 describe-network-interfaces --filters Name=requester-id,Values="*${requester_id}" > "${eni_list_file}" || return $?

    for attachment_id in $( jq -r '.NetworkInterfaces[].Attachment.AttachmentId' < "${eni_list_file}" ) ; do
        if [[ -n "${attachment_id}" ]]; then
            info "Detaching ${attachment_id} ..."
            aws --region "${region}" ec2 detach-network-interface --attachment-id "${attachment_id}" || return $?
        fi
    done
    for network_interface_id in $( jq -r '.NetworkInterfaces[].NetworkInterfaceId' < "${eni_list_file}" ) ; do
        if [[ -n "${network_interface_id}" ]]; then
            info "Deleting ${network_interface_id} ..."
            aws --region "${region}" ec2 wait network-interface-available --network-interface-id "${network_interface_id}" || return $?
            aws --region "${region}" ec2 delete-network-interface --network-interface-id "${network_interface_id}" || return $?
        fi
    done
}
