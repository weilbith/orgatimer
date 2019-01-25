#!/bin/bash
# shellcheck disable=SC1090 

# Directory that is used as semaphore.
BLOCK_FOLDER="$XDG_RUNTIME_DIR/organizer_cash_block"

# ---


# Functions

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
