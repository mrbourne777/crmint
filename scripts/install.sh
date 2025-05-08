#!/bin/bash
#
# Copyright 2023 Google Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

mkdir -p ~/.cloudshell
touch ~/.cloudshell/no-apt-get-warning

# Function to ensure gcloud authentication
function ensure_gcloud_auth() {
  # Get the list of accounts and select the first one if multiple accounts exist
  ACTIVE_ACCOUNT=$(gcloud auth list --format="value(account)" | head -n 1)

  if [ -z "$ACTIVE_ACCOUNT" ]; then
    echo "No active Google Cloud account is selected."
    echo "Please authenticate with your Google Cloud account to continue."
    gcloud auth login
    if [ $? -ne 0 ]; then
      echo "Authentication failed, exiting."
      exit 1
    fi
  else
    echo "Active Google Cloud account is set to $ACTIVE_ACCOUNT"
  fi
}

# Function to ensure gcloud project is set
function ensure_gcloud_project_set() {
  CURRENT_PROJECT=$(gcloud config get-value project)

  if [ -z "$CURRENT_PROJECT" ]; then
    echo "No Google Cloud project is currently set."
    read -p "Please enter your Google Cloud project ID to continue: " PROJECT_ID
    if [ -z "$PROJECT_ID" ]; then
      echo "No project ID provided, exiting."
      exit 1
    else
      gcloud config set project "$PROJECT_ID"
      echo "Project set to $PROJECT_ID"
    fi
  else
    echo "Current Google Cloud project is set to $CURRENT_PROJECT"
  fi
}

# Function to parse command line arguments
function parse_command_line_arguments() {
  TARGET_BRANCH=$1
  RUN_COMMAND=$2
  COMMAND_OPTIONS=$3
  USE_VPC_FLAG=""
  CURRENT_DIR=$(pwd)

  if [[ "$4" == "--use_vpc" ]]; then
    USE_VPC_FLAG="--use_vpc"
  fi

  case "${RUN_COMMAND}" in
    --bundle)
      COMMAND="crmint bundle install ${USE_VPC_FLAG}"
      ;;
    *)
      echo "Unknown command: ${RUN_COMMAND}" >&2
      exit 2
      ;;
  esac
  if [[ ! -z "$COMMAND" ]]; then
    echo "Will run the following command after installing the CRMint command line"
    echo " ${COMMAND} ${COMMAND_OPTIONS}"
  fi
}

# Function to clone and checkout repository
function clone_and_checkout_repository() {
  TARGET_REPO_URL="https://github.com/instant-bqml/crmint.git"
  TARGET_REPO_NAME="crmint"
  CLONE_DIR="$HOME/$TARGET_REPO_NAME"

  if [ -d "$CLONE_DIR" ]; then
    echo "Found existing directory for $TARGET_REPO_NAME"
    cd "$CLONE_DIR"

    CURRENT_REPO_URL=$(git config --get remote.origin.url)
    if [ "$CURRENT_REPO_URL" != "$TARGET_REPO_URL" ]; then
      echo "Switching remote URL from $CURRENT_REPO_URL to $TARGET_REPO_URL"
      git remote set-url origin "$TARGET_REPO_URL"
    fi
    git fetch --all --quiet
    git reset --hard origin/$TARGET_BRANCH
    sudo git clean -fdx || echo "Warning: Some files could not be removed. You may need to manually remove files with elevated permissions."
    git checkout $TARGET_BRANCH
  else
    git clone "$TARGET_REPO_URL" "$CLONE_DIR"
    echo "Cloned $TARGET_REPO_NAME repository to your home directory: $HOME."
    cd "$CLONE_DIR"
    git checkout $TARGET_BRANCH
  fi
}

# Function to install the command line using Python 3.9
function install_command_line() {
  # Remove existing virtual environment if it exists
  if [ -d .venv ]; then
    rm -rf .venv
  fi

  # Install Python 3.9 and its venv module
  echo "Installing Python 3.9 and necessary packages..."
  sudo apt-get update
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository ppa:deadsnakes/ppa -y &> /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3.9 python3.9-venv python3.9-dev

  # Verify Python 3.9 installation
  if ! command -v python3.9 &> /dev/null; then
    echo "Python 3.9 installation failed, exiting."
    exit 1
  fi
  echo "Python 3.9 version: $(python3.9 --version)"

  # Create virtual environment using Python 3.9
  echo "Creating virtual environment with Python 3.9..."
  python3.9 -m venv .venv

  # Activate the virtual environment
  echo "Activating virtual environment..."
  . .venv/bin/activate
  
  # Upgrade pip, setuptools, wheel, and packaging in a single command to avoid conflicts
  echo "Upgrading pip, setuptools, wheel, and packaging..."
  pip install --upgrade pip setuptools wheel packaging &> /dev/null

  # Proceed to install the cli package
  echo "Installing CRMint CLI package..."
  pip install --quiet --config-settings editable_mode=compat -e cli/
}

# Function to add wrapper function to .bashrc
function add_wrapper_function_to_bashrc() {
  echo -e "\\nAdding a bash function to your $HOME/.bashrc file."

  cat <<EOF >>$HOME/.bashrc

# CRMint wrapper function.
# Automatically activates the virtualenv and makes the command
# accessible from all directories
function crmint {
  CURRENT_DIR=\$(pwd)
  cd \$HOME/crmint
  . .venv/bin/activate
  command crmint \$@ || return
  deactivate
  cd "\$CURRENT_DIR"
}
EOF
}

# Function to run the specified command
function run_command_line() {
  if [[ ! -z "$COMMAND" ]]; then
    hash -r
    eval "${COMMAND} ${COMMAND_OPTIONS}"
  else
    echo -e "\nSuccessfully installed the CRMint command-line."
    echo "You can use it now by typing: crmint --help"
    exec bash
  fi
}

# Main script execution
parse_command_line_arguments "$@"
ensure_gcloud_project_set
ensure_gcloud_auth
clone_and_checkout_repository
install_command_line
add_wrapper_function_to_bashrc
cd "$CURRENT_DIR"
run_command_line
