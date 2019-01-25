#!/bin/bash
# shellcheck disable=SC1090 
#
# Manage a single tool process.
# Executes the tool initially once.
# Afterwards it gets executed periodically.
# The period is as long as the tools configured value plus the execution time in
# each interval.

# Parse the arguments.
COMMAND="$1" # Command property of the tool.
INTERVAL="$2" # Interval property of the tool.
RECIPIENT="$3" # Recipient property of the tool [optional]
GRIP="$4" # Grip property of the tool [optional]
LOG="$5" # Log file name if logging is requested [optional]

# Parse parameter
GPG_REQUIRED=false
[[ -n "$2" ]] && [[ -n "$3" ]] && GPG_REQUIRED=true

# ---


# Load additional functionality in case it is needed.
if $GPG_REQUIRED; then
  source "$ORGATIMER_COMPONENT_GPG_UTILS" # Additional functions to interact with GnuPG.
  source "$ORGATIMER_COMPONENT_BLOCKER" # Utility functions which provide some semaphore functionality.
fi

# ---


# Functions

# Execute a tool for a single time.
# Checks if the tool is based on GPG key and make therefore sure the
# password for the key is cached before running the tool itself.
# Logs the tools ouput if requested.
#
function executeTool {
  echo "$COMMAND"
  return

  # Update GPG cache if required.
  if $GPG_REQUIRED; then
    update_gpg_cache "$RECIPIENT" "$GRIP" || return
  fi
  
  # Execute tool.
  if [[ -n "$LOG" ]]; then
    local file="${LOG_DIR}/${LOG}.log"
    echo -e "\n\n$(date)\n" >> "$file"
    $COMMAND 2>&1 >> "$file"
  
  else
    $COMMAND
  fi
}


# Getting started.
executeTool

while : ; do
  sleep "$INTERVAL"
  executeTool
done
