#!/bin/bash
# shellcheck disable=SC1090 

# Name used for paths specific for this application.
export NAME="orgatimer"

# Make sure the XDG environment variables are defined.
[[ -z "$XDG_CONFIG_HOME" ]] && export XDG_CONFIG_HOME="$HOME/.config"
[[ -z "$XDG_CACHE_HOME" ]] && export XDG_CACHE_HOME="$HOME/.cache"
[[ -z "$XDG_RUNTIME_DIR" ]] && export XDG_RUNTIME_DIR="/tmp"


# Paths
export ORGATIMER_DIR_CONFIG_USER
export ORGATIMER_DIR_CONFIG_GLOBAL
export ORGATIMER_DIR_LOGS

ORGATIMER_DIR_CONFIG_GLOBAL="/etc/$NAME"
ORGATIMER_DIR_CONFIG_USER="$XDG_CONFIG_HOME/$NAME"
ORGATIMER_DIR_LOGS="$XDG_CACHE_HOME/$NAME"
ORGATIMER_DIR_COMPONENTS="/usr/lib/$NAME/components"
[[ "$1" == "test" ]] && ORGATIMER_DIR_COMPONENTS="$(dirname "${BASH_SOURCE[0]}")/components" && echo 'jpp'


# Files
export ORGATIMER_FILE_CONFIG_GLOBAL
export ORGATIMER_FILE_CONFIG_USER

ORGATIMER_FILE_CONFIG_GLOBAL="$ORGATIMER_DIR_CONFIG_GLOBAL/$NAME.conf"
ORGATIMER_FILE_CONFIG_USER="$ORGATIMER_DIR_CONFIG_USER/$NAME.conf"


# Component names
export ORGATIMER_COMPONENT_BLOCKER
export ORGATIMER_COMPONENT_GPG_UTILS
export ORGATIMER_COMPONENT_TOOL_HANDLER

ORGATIMER_COMPONENT_BLOCKER="$ORGATIMER_DIR_COMPONENTS/Blocker.sh"
ORGATIMER_COMPONENT_GPG_UTILS="$ORGATIMER_DIR_COMPONENTS/GpgUtils.sh"
ORGATIMER_COMPONENT_TOOL_HANDLER="$ORGATIMER_DIR_COMPONENTS/ToolHandler.sh"

# ---


# Load configurations
# Load the default and user configurations.
source "$ORGATIMER_FILE_CONFIG_GLOBAL" # Default values for all necessary variables.
[[ -f "$ORGATIMER_FILE_CONFIG_USER" ]] && \
  source "$ORGATIMER_FILE_CONFIG_USER" # Load after default values to be able to overwrite them (only if exist).

# Source exported functionality.
source "$ORGATIMER_COMPONENT_BLOCKER" # Utility functions which provide some semaphore functionality.

# ---


# Close procedure setup
# List of all process identifiers of the subscripts which handle the segments.
PID_LIST=""

# Execute cleanup function at script exit.
trap cleanup EXIT

# ---


# Functions

# Cleanup the script when it gets exited.
# This will kill all started child processes.
# Also included is to remove the process identifier file.
#
function cleanup {
  rm -f "$PID_FILE"

  # Iterate over all process identifiers to kill them.
  for pid in $PID_LIST ; do
    kill $pid
  done
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
  mkdir -p "$ORGATIMER_DIR_LOGS"
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


# Spawn a tool handler for each listed tool.
# Therefore parse the tools properties and forward them to the handler.
# Tools handler will be run as subprocess.
#
function initTools {
  for tool in "${TOOL_LIST[@]}"; do
    local command interval internet log recipient grip
    command=$(get_tool_property "$tool" "$TOOL_KEY_COMMAND")
    interval=$(get_tool_property "$tool" "$TOOL_KEY_INTERVAL")
    internet=$(get_tool_property "$tool" "$TOOL_KEY_INTERNET")
    log=$(get_tool_property "$tool" "$TOOL_KEY_LOG")
    recipient=$(get_tool_property "$tool" "$TOOL_KEY_RECIPIENT")
    grip=$(get_tool_property "$tool" "$TOOL_KEY_GRIP")

    bash "$ORGATIMER_COMPONENT_TOOL_HANDLER" \
      "$command" "$interval" \
      "$internet" "$log" \
      "$recipient" "$grip" \
      &

    # Store the process identifier to be able to kill it later on.
    PID_LIST="$PID_LIST $!"
  done
}


# Getting started
initialize
initTools
wait
