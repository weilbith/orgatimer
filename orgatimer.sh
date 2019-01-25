#!/bin/bash

# General stuff
PID_FILE=$XDG_RUNTIME_DIR/orgatimer/pid
LOG_DIR="$XDG_CACHE_HOME/orgatimer"

# Tool keys
TOOL_KEY_COMMAND="command"
TOOL_KEY_INTERVAL="interval"
TOOL_KEY_RECIPIENT="recipient"
TOOL_KEY_GRIP="grip"
TOOL_KEY_LOG="log"

# Tools
## Notmuch
declare -A TOOL_NOTMUCH
TOOL_NOTMUCH[$TOOL_KEY_COMMAND]="notmuch new"
TOOL_NOTMUCH[$TOOL_KEY_INTERVAL]="1m"

## iSync
declare -A TOOL_ISYNC
TOOL_ISYNC[$TOOL_KEY_COMMAND]="mbsync -c $XDG_CONFIG_HOME/isync/mbsyncrc -a"
TOOL_ISYNC[$TOOL_KEY_INTERVAL]="5m"
TOOL_ISYNC[$TOOL_KEY_RECIPIENT]="D53C38FA78DFF2B4279F91B052FCDAA1483DA28D"
TOOL_ISYNC[$TOOL_KEY_GRIP]="27D59D1FAFF3B7629E233A645FF351E9C30B8948"
TOOL_ISYNC[$TOOL_KEY_LOG]="isync"

## VDirSyncer
### Discover
declare -A TOOL_VDIRSYNCER_DISCOVER
TOOL_VDIRSYNCER_DISCOVER[$TOOL_KEY_COMMAND]="yes | vdirsyncer discover"
TOOL_VDIRSYNCER_DISCOVER[$TOOL_KEY_INTERVAL]="1h"
TOOL_VDIRSYNCER_DISCOVER[$TOOL_KEY_RECIPIENT]="D53C38FA78DFF2B4279F91B052FCDAA1483DA28D"
TOOL_VDIRSYNCER_DISCOVER[$TOOL_KEY_GRIP]="27D59D1FAFF3B7629E233A645FF351E9C30B8948"

### Discover
declare -A TOOL_VDIRSYNCER_SYNC
TOOL_VDIRSYNCER_SYNC[$TOOL_KEY_COMMAND]="vdirsyncer sync"
TOOL_VDIRSYNCER_SYNC[$TOOL_KEY_INTERVAL]="10m"
TOOL_VDIRSYNCER_SYNC[$TOOL_KEY_RECIPIENT]="${TOOL_VDIRSYNCER_DISCOVER[$TOOL_KEY_RECIPIENT]}"
TOOL_VDIRSYNCER_SYNC[$TOOL_KEY_GRIP]="${TOOL_VDIRSYNCER_DISCOVER[$TOOL_KEY_GRIP]}"

# List of all tools.
TOOL_LIST=(
  TOOL_NOTMUCH
  TOOL_ISYNC
  # TOOL_VDIRSYNCER_DISCOVER
  # TOOL_VDIRSYNCER_SYNC
)

## Caching stuff.
TMP_RAW_FILE="/tmp/organizer_cash"
TMP_ENCRYPTED_FILE="${TMP_RAW_FILE}.gpg"

## Blocking stuff.
BLOCK_FOLDER="/tmp/organizer_cash_block"


# Tidy up when done.
# This includes to remove the process identifier file.
#
function finish {
  rm -f "$PID_FILE"
}

# Read a property value of a tool by a given key.
# Defined for simplify the usage of nested associative arrays.
#
# Arguments:
#   $1 - tool to read from (associative array)
#   $2 - key for the property to read
#
# Returns:
#   The associated property value
#
function get_tool_property {
  object=$(declare -p "$1")
  eval "declare -A tool="${object#*=}
  echo "${tool[$2]}"
}

# Enable the block.
# Entry part of the semaphore.
# Waits until the block is free again and then blocks itself.
# Differs between immediately blocks and waiting for it.
# Waiting before try to block again includes some randomness to avoid parallel
# block approaches.
#
# Returns:
#   0 - block was immediately set
#   1 - block was set after waiting for current block to be released
#
function block_enable {
  [[ ! -d "$BLOCK_FOLDER" ]] && mkdir "$BLOCK_FOLDER" && return 0

  while : ; do
    mkdir "$BLOCK_FOLDER" 2> /dev/null && return 1
    sleep 1.$(( ( RANDOM % 10  ) + 1 ))s
  done
}

# Disable the block.
# Releasing part of the semaphore mechanism.
# Used to avoid multiple user interactions at once.
#
function block_disable {
  rm -rf "$BLOCK_FOLDER"
}

# Connect to the GPG-Agent to check the cache status for a specific key.
# Succeed if the password is cached.
# Else fail.
#
# Arguments:
#   $1 - the key grip to check for
#
# Returns:
#   0 - if the password for the key is cached
#   1 - otherwise
#
function check_gpg_cache {
  cached=$(\
    gpg-connect-agent 'keyinfo --list' /bye | \
    grep "$1" | \
    awk 'BEGIN{CACHED=0} /^S/ {if($7==1){CACHED=1}} END{if($0!=""){print CACHED} else {print "none"}}' \
  )

  [[ $cached -gt 0 ]] && return 0 || return 1
}

# Make sure the password for a specific key is cached.
# If the password is not cached already or has expired,
# the user is interactively requested to update the cache.
#
# Arguments:
#   $1 - key id that should been updated
#   $2 - key grip for the GPG-Agent
#
# Returns:
#   0 - if password for key is cached in the end
#   1 - if a possibly required update by the user was not successful
#
function update_gpg_cache {
  # Check if password is cached by GPG-Agent.
  check_gpg_cache "$2" && return 0

  # Enable block for updating cache by possibly user interaction.
  if ! block_enable; then
    # Has waited for block.
    # Recheck the cache if it was updated by blocking update process.
    check_gpg_cache "$2" && block_disable && return 0
  fi

  # Get the password interactively by the user.
  # Create and encrypt a temporally file.
  rm -f "$TMP_ENCRYPTED_FILE"
  touch "$TMP_RAW_FILE"
  gpg --encrypt --recipient "$1" "$TMP_RAW_FILE"

  # Decrypt the temporally file which cause user interaction with PIN entry.
  command=$(echo \
    'echo "Organizer key password cache has expired!";' \
    'read -p "Update cache? [Y/n]: " answer;' \
    'if [[ "${answer}" == "" || "${answer}" == "y" ]]; then' \
    "gpg --decrypt /tmp/organizer_cash.gpg;" \
    'fi' \
  )

  urxvt -name organized-poller -geometry 45x5 -e sh -c "$command"

  # Tidy up.
  rm -f "$TMP_RAW_FILE" "$TMP_ENCRYPTED_FILE"

  # Release the block again, so waiting updates in parallel can continue.
  block_disable

  # Check again if password is now cached so updating the cache has worked out.
  check_gpg_cache "$2" && return 0 || return 1
}

# Make sure this script is running only once at the same time.
# Kill the over process if so, by using its cached process id.
# If shut down the parallel process is not possible, exit itself.
# Also makes sure a possibly remaining old block is purged,
# as well as allow logging.
#
function initialize {
  if [[ -f "$PID_FILE" ]] ; then
    # Read in process identifier and try to kill it.
    pid=$(cat "$PID_FILE")
    kill "$pid"
    
    # Check if process is still running.
    if ps -p "$pid" > /dev/null ; then
      echo "Can't shut down already running orgatimer. Exit here."
      exit 1
    fi
  fi

  # Make sure the folder for the process identifier file exists.
  folder=$(dirname "$PID_FILE")
  [[ ! -d "$folder" ]] && mkdir -p "$folder"

  # Write own process identifier into the file.
  echo "$$" > "$PID_FILE"

  block_disable
  mkdir -p "$LOG_DIR"
}

# Spawn a tool handler for each listed tool.
# Therefore parse the tools properties and forward them to the handler.
# Tools handler will be run as subprocess.
#
function spawnTools {
  for tool in "${TOOL_LIST[@]}"; do
    local command interval recipient grip log
    command=$(get_tool_property "$tool" "$TOOL_KEY_COMMAND")
    interval=$(get_tool_property "$tool" "$TOOL_KEY_INTERVAL")
    recipient=$(get_tool_property "$tool" "$TOOL_KEY_RECIPIENT")
    grip=$(get_tool_property "$tool" "$TOOL_KEY_GRIP")
    log=$(get_tool_property "$tool" "$TOOL_KEY_LOG")

    toolHandler "$command" "$interval" "$recipient" "$grip" "$log" &
  done
}

# Execute a tool for a single time.
# Checks if the tool is based on GPG key and make therefore sure the
# password for the key is cached before running the tool itself.
# Logs the tools ouput if requested.
#
# Arguments:
#   $1 - command property of the tool
#   $2 - recipient property of the tool [optional]
#   $3 - grip property of the tool [optional]
#   $4 - log file name if logging is requested [optional]
#
function executeTool {
  # Check if a GPG key must be available.
  if [[ -n "$2" ]] && [[ -n "$3" ]]; then
    update_gpg_cache "$2" "$3" || return
  fi

  # Execute tool.
  if [[ -n "$4" ]]; then
    local file="${LOG_DIR}/${4}.log"
    echo -e "\n\n$(date)\n" >> "$file"
    $1 2>&1 >> "$file"

  else
    $1
  fi
}

# Manage a single tool process.
# Executes the tool initially once.
# Afterwards it gets executed periodically.
# The period is as long as the tools configured value plus the execution time in
# each interval.
#
# Arguments:
#   $1 - command property of the tool
#   $2 - interval property of the tool
#   $3 - recipient property of the tool [optional]
#   $4 - grip property of the tool [optional]
#   $5 - log file name if logging is requested [optional]
#
function toolHandler {
  executeTool "$1" "$3" "$4"

  while : ; do
    sleep "$2"
    executeTool "$1" "$3" "$4" "$5"
  done
}


# Getting started
trap finish EXIT
initialize
spawnTools
wait
