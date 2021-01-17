#!/bin/bash
set -xueo pipefail

# TODO: make sdist work on all, it currently fails for clash-cosim
cabal v2-sdist clash-prelude clash-lib clash-ghc

# test that we can create a build plan with the index-state in cabal.project
set +u
if [[ "$GHC_HEAD" != "yes" ]]; then
  mv cabal.project.local cabal.project.local.disabled
  cabal v2-build --dry-run all > /dev/null || (echo Maybe the index-state should be updated?; false)
  mv cabal.project.local.disabled cabal.project.local
fi
set -u

# Build with installed constraints for packages in global-db
echo cabal v2-build $(ghc-pkg list --global --simple-output --names-only | sed 's/\([a-zA-Z0-9-]\{1,\}\) */--constraint="\1 installed" /g') all | sh

# Build with default constraints
cabal v2-build all --write-ghc-environment-files=always
