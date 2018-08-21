#! /bin/bash
#
# set_up_git.sh
# Copyright (C) 2018 Till Hofmann <hofmann@kbsg.rwth-aachen.de>
#
# Distributed under terms of the MIT license.
#

set -eou pipefail

if [ -z $REPO_DIR ] ; then
  echo >&2 "fatal: REPO_DIR not set."
  exit 1
fi

if [ ! -d $REPO_DIR ] ; then
  mkdir -p $REPO_DIR
  pushd $REPO_DIR
  git clone --bare $1 .
  popd
fi

pushd $REPO_DIR
git fetch --tags
popd
