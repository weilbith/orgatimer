#!/bin/bash
# shellcheck disable=SC1090,SC2002
#
# Manage a single tool process.
# Executes the tool initially once.
# Afterwards it gets executed periodically.
# The period is as long as the tools configured value plus the execution time in
# each interval.

# Parse the arguments.
COMMAND="$1" # Command property of the tool.
INTERVAL="$2" # Interval property of the tool.
INTERNET="$3" # Boolean if internet is necessary [optional]
LOG="$4" # Log file name if logging is requested [optional]
RECIPIENT="$5" # Recipient property of the tool [optional]
GRIP="$6" # Grip property of the tool [optional]

# Parse parameter
GPG_REQUIRED=false
[[ -n "$RECIPIENT" ]] && [[ -n "$GRIP" ]] && GPG_REQUIRED=true
[[ -n "$INTERNET" ]] && $INTERNET || INTERNET=false
INTERVAL_INTERVAL=$INTERVAL

# ---


# Sourcing

## Load additional functionality in case it is needed.
if $GPG_REQUIRED; then
  source "$ORGATIMER_COMPONENT_GPG_UTILS" # Additional functions to interact with GnuPG.
  source "$ORGATIMER_COMPONENT_BLOCKER" # Utility functions which provide some semaphore functionality.
fi

## Get specific configuration values (user declaration overwrites global)
source <(cat "$ORGATIMER_FILE_CONFIG_GLOBAL" | grep -E "^INTERVAL_WITHOUT_INTERNET|^TERMINAL_COMMAND")
source <(cat "$ORGATIMER_FILE_CONFIG_USER" | grep -E "^INTERVAL_WITHOUT_INTERNET|^TERMINAL_COMMAND")

# ---


# Functions

# Check if the tool requires an internet connection.
# If not the function is successful per default,
# else it check if a connection could be established.
# The outcome is depending on this check,
# as well as the interval for this handler will be updated.
# The intention is to use a possibly shorter check interval as long as no connection
# is available, since the tool is not running in the meantime.
#
# Returns:
#   0 - if tool require no internet or connection is available
#   1 - else
#
function checkInternetAvailability {
  # Check if the tools needs internet.
  if ! $INTERNET; then
    return 0
  fi

  # Check if internet is available and alter the interval duration.
  if ping -q -w 5 -c 1 github.com > /dev/null; then
    INTERVAL_INTERVAL=$INTERVAL
    return 0

  else
    INTERVAL_INTERVAL=$INTERVAL_WITHOUT_INTERNET
    return 1
  fi
}


# Execute a tool for a single time.
# Checks if the tool is based on GPG key and make therefore sure the
# password for the key is cached before running the tool itself.
# Logs the tools ouput if requested.
#
function executeTool {
  # Update GPG cache if required.
  if $GPG_REQUIRED; then
    update_gpg_cache "$RECIPIENT" "$GRIP" || return
  fi
  
  # Execute tool.
  if [[ -n "$LOG" ]]; then
    local file="${ORGATIMER_DIR_LOGS}/${LOG}.log"
    echo -e "\n\n$(date)\n" >> "$file"
    { $COMMAND >> "$file"; } 2>&1
  
  else
    $COMMAND
  fi
}


# Getting started.
checkInternetAvailability && executeTool

while : ; do
  sleep "$INTERVAL_INTERVAL"
  checkInternetAvailability && executeTool
done
