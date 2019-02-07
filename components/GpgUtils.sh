#!/bin/bash

# Temporally files achieve updating.
TMP_RAW_FILE="${XDG_RUNTIME_DIR}/${NAME}/organizer_cache"
TMP_ENCRYPTED_FILE="${TMP_RAW_FILE}.gpg"

# ---


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
    "gpg --decrypt $TMP_ENCRYPTED_FILE;" \
    'fi'
  )

  $TERMINAL_COMMAND sh -c "$command"

  # Tidy up.
  rm -f "$TMP_RAW_FILE" "$TMP_ENCRYPTED_FILE"

  # Release the block again, so waiting updates in parallel can continue.
  block_disable

  # Check again if password is now cached so updating the cache has worked out.
  check_gpg_cache "$2" && return 0 || return 1
}
