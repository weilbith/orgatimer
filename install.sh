#!/bin/bash
#
# NAME
#   Orgatimer Installer
#
# SYNOPSIS
#   install.sh <command>
#
# DESCRIPTION
#   Installation/removal of the Orgatimer application.
#   Requires to be root or be part of the group sudo to run successfully.
#
# COMMANDS
#   help      Print out this user information how to use.
#
#   install   Install the application with all dependencies.
#             This includes providing the global configuration and default segments.
#
#   remove    Remove the whole application with all sources.
#             This includes the removal of the users cache and runtime data.
#             This does not not remove custom configuration.
#

# Quit on any error.
set -e


# Variables
NAME="orgatimer"
SOURCE="https://github.com/weilbith/orgatimer.git"
PERMISSION_PREFIX=""

# Operations
COMMAND_INSTALL="install"
COMMAND_REMOVE="remove"
COMMAND_HELP="help"

# Make sure the XDG environment variables are defined.
[[ -z "$XDG_CONFIG_HOME" ]] && XDG_CONFIG_HOME="$HOME/.config"
[[ -z "$XDG_CACHE_HOME" ]] && XDG_CACHE_HOME="$HOME/.cache"
[[ -z "$XDG_RUNTIME_DIR" ]] && XDG_RUNTIME_DIR="/tmp"

# Paths
DIR_BIN="/bin"
DIR_TMP="/tmp/${NAME}_sources"
DIR_LIB="/usr/lib/${NAME}"
DIR_SHARE="/usr/share/${NAME}"
DIR_CONFIG="/etc/${NAME}"
DIR_CACHE="${XDG_CACHE_HOME}/${NAME}"
DIR_RUNTIME="${XDG_RUNTIME_DIR}/${NAME}"

# Files
FILE_CONFIG_CUSTOM="${XDG_CONFIG_HOME}/${NAME}/${NAME}.conf"

# ---


# Functions

# Installation of the application.
# This place all sources at their places and
# make necessary structure available.
#
function install {
  echo -e "\\nCreate all necessary directories..."
  "$PERMISSION_PREFIX"mkdir -p "$DIR_LIB"
  "$PERMISSION_PREFIX"mkdir -p "$DIR_SHARE"
  "$PERMISSION_PREFIX"mkdir -p "$DIR_CONFIG"

  rm -rf "$DIR_TMP"
  git clone --depth 1 --recurse-submodules "$SOURCE" "$DIR_TMP"
  git rev-parse HEAD > "$DIR_SHARE/version"

  echo -e "\\nCopy all sources to their belonging locations..."
  "$PERMISSION_PREFIX"cp -f "${DIR_TMP}/${NAME}.sh" "$DIR_LIB"
  "$PERMISSION_PREFIX"cp -rf "${DIR_TMP}/components" "$DIR_LIB"
  "$PERMISSION_PREFIX"cp -f "${DIR_TMP}/${NAME}.conf" "$DIR_CONFIG"

  echo -e "\\nLink the executable..."
  "$PERMISSION_PREFIX"ln -sf "${DIR_LIB}/${NAME}.sh" "${DIR_BIN}/${NAME}"

  # Cleanup
  rm -rf "$DIR_TMP"
}


# Remove of the application.
# This deletes all possibly installed sources.
#
function remove {
  echo -e "\\nRemove all references..."
  "$PERMISSION_PREFIX"rm -rf "$DIR_LIB"
  "$PERMISSION_PREFIX"rm -rf "$DIR_SHARE"
  "$PERMISSION_PREFIX"rm -rf "$DIR_CONFIG"
  "$PERMISSION_PREFIX"rm -rf "$DIR_CACHE"
  "$PERMISSION_PREFIX"rm -rf "$DIR_RUNTIME"

  echo -e "\\nIn case you have stored a custom configuration at ${FILE_CONFIG_CUSTOM}, please make sure to remove it by yourself!"
}


# Print the header of this script as help.
# The header ends with the first empty line.
#
function help {
  local file="${BASH_SOURCE[0]}"
  sed -e '/^$/,$d; s/^#//; s/^\!\/bin\/bash//' "$file"
}


# Getting started.
if [[ "$1" == "$COMMAND_HELP" ]] ; then
  help

else
  # Make sure to have enough permissions.
  echo -e "\\nCheck for permissions..."
  if [[ "$EUID" -ne 0 ]] ; then
    if [[ $(getent group sudo) = *"$USER"* ]] ;  then
      echo -e "\\nUser is part of group sudo. Request user for authorization..."
      PERMISSION_PREFIX="sudo "

    else
      echo -e "\\nYou must be root or be part of the group sudo!"
      exit 1
    fi
  else 
    echo -e "\\nExecuting as root. Permissions granted."
  fi

  # Check what should be done.
  if [[ "$1" == "$COMMAND_INSTALL" ]] ; then
    install

  elif [[ "$1" == "$COMMAND_REMOVE" ]] ; then
    remove

  else
    echo -e "\\nUnknown command '${1}'! Call '${COMMAND_HELP}' to get information how to use."
  fi
fi
