#!/usr/bin/env bash

release_branches=($(git branch -r | grep -oP '(?<=origin\/)release\/.*' | sort -k4 -t. -nr))
RELEASE_BRANCH="${release_branches[0]:-}"

if [ -z "${RELEASE_BRANCH}" ]; then
  echo "ERROR: Failed to match release branch from the following:"
  git branch -r
  exit 1
fi

RELEASE_VERSION="${RELEASE_BRANCH#release/}"
export RELEASE_BRANCH RELEASE_VERSION
echo "INFO: RELEASE_BRANCH=${RELEASE_BRANCH} RELEASE_VERSION=${RELEASE_VERSION}"