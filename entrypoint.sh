#!/bin/bash -l

set -x
set -e

OLD_APT_DEPENDENCIES=$1
CODECOV_ENABLED=$2
CODECOV_TOKEN_PRIVATE_REPOS=$3
DEPRECATED_CODECOV_TOKEN=$4
CMAKE_ARGS=$5
DOXYGEN_ENABLED=$6
TESTS_ENABLED=$7
CPPLINT_ENABLED=$8
CPPCHECK_ENABLED=$9

# keep the previous behaviour of running codecov if old token is set
[ -n "${DEPRECATED_CODECOV_TOKEN}" ] && CODECOV_ENABLED=1

export DEBIAN_FRONTEND="noninteractive"

cd "$GITHUB_WORKSPACE"

echo ::group::Install tools: apt
apt update 2>&1
apt -y install \
  build-essential \
  cmake \
  cppcheck \
  curl \
  git \
  gnupg \
  lcov \
  lsb-release \
  python3-pip \
  wget

if [ -n "$DOXYGEN_ENABLED" ] && ${DOXYGEN_ENABLED} ; then
  apt -y install doxygen
fi

# Add the workspace as a safe directory in the global git config. This ensures that any
# even if the workspace is owned by another user, git commands still work.
# See https://github.com/actions/checkout/issues/760
git config --global --add safe.directory $GITHUB_WORKSPACE

SYSTEM_VERSION=`lsb_release -cs`

SOURCE_DEPENDENCIES="`pwd`/.github/ci/dependencies.yaml"
SOURCE_DEPENDENCIES_VERSIONED="`pwd`/.github/ci-$SYSTEM_VERSION/dependencies.yaml"
SCRIPT_BEFORE_DEP_COMPILATION="`pwd`/.github/ci/before_dep_compilation.sh"
SCRIPT_BEFORE_DEP_COMPILATION_VERSIONED="`pwd`/.github/ci-$SYSTEM_VERSION/before_dep_compilation.sh"
SCRIPT_BEFORE_CMAKE="`pwd`/.github/ci/before_cmake.sh"
SCRIPT_BEFORE_CMAKE_VERSIONED="`pwd`/.github/ci-$SYSTEM_VERSION/before_cmake.sh"
SCRIPT_BETWEEN_CMAKE_MAKE="`pwd`/.github/ci/between_cmake_make.sh"
SCRIPT_BETWEEN_CMAKE_MAKE_VERSIONED="`pwd`/.github/ci-$SYSTEM_VERSION/between_cmake_make.sh"
SCRIPT_AFTER_MAKE="`pwd`/.github/ci/after_make.sh"
SCRIPT_AFTER_MAKE_VERSIONED="`pwd`/.github/ci-$SYSTEM_VERSION/after_make.sh"
SCRIPT_AFTER_MAKE_TEST="`pwd`/.github/ci/after_make_test.sh"
SCRIPT_AFTER_MAKE_TEST_VERSIONED="`pwd`/.github/ci-$SYSTEM_VERSION/after_make_test.sh"

echo ::group::Build folder
mkdir build
cd build
echo ::endgroup::


echo ::group::cmake
if [ -n "$CODECOV_ENABLED" ] && ${CODECOV_ENABLED} ; then
  cmake .. $CMAKE_ARGS -DCMAKE_BUILD_TYPE=coverage
else
  cmake .. $CMAKE_ARGS
fi
echo ::endgroup::

echo ::group::cpplint
if [ -n "$CPPLINT_ENABLED" ] && ${CPPLINT_ENABLED} ; then
  if grep -iq cpplint Makefile; then
    make cpplint 2>&1
  fi
fi
echo ::endgroup

echo ::group::cppcheck
if [ -n "$CPPCHECK_ENABLED" ] && ${CPPCHECK_ENABLED} ; then
  if grep -iq cppcheck Makefile; then
    make cppcheck 2>&1
  fi
fi
echo ::endgroup

if [ -n "$DOXYGEN_ENABLED" ] && ${DOXYGEN_ENABLED} ; then
  echo ::group::Documentation check
  make doc 2>&1
  bash <(curl -s https://raw.githubusercontent.com/gazebosim/gz-cmake/main/tools/doc_check.sh)
  echo ::endgroup::
fi

if [ -f "$SCRIPT_BETWEEN_CMAKE_MAKE" ] || [ -f "$SCRIPT_BETWEEN_CMAKE_MAKE_VERSIONED" ] ; then
  echo ::group::Script between cmake and make
  if [ -f "$SCRIPT_BETWEEN_CMAKE_MAKE" ] ; then
    . $SCRIPT_BETWEEN_CMAKE_MAKE
  fi
  if [ -f "$SCRIPT_BETWEEN_CMAKE_MAKE_VERSIONED" ] ; then
    . $SCRIPT_BETWEEN_CMAKE_MAKE_VERSIONED
  fi
  echo ::endgroup::
fi

echo ::group::make
make -j4
echo ::endgroup::

if [ -f "$SCRIPT_AFTER_MAKE" ] || [ -f "$SCRIPT_AFTER_MAKE_VERSIONED" ] ; then
  echo ::group::Script after make
  if [ -f "$SCRIPT_AFTER_MAKE" ] ; then
    . $SCRIPT_AFTER_MAKE
  fi
  if [ -f "$SCRIPT_AFTER_MAKE_VERSIONED" ] ; then
    . $SCRIPT_AFTER_MAKE_VERSIONED
  fi
  echo ::endgroup::
fi

if [ -n "$TESTS_ENABLED" ] && ${TESTS_ENABLED} ; then
  echo ::group::make test
  export CTEST_OUTPUT_ON_FAILURE=1
  cd "$GITHUB_WORKSPACE"/build
  cat /proc/sys/kernel/core_pattern
  ulimit -c unlimited
  make test
  echo ::endgroup::
fi

if [ -f "$SCRIPT_AFTER_MAKE_TEST" ] || [ -f "$SCRIPT_AFTER_MAKE_TEST_VERSIONED" ] ; then
  echo ::group::Script after make test
  if [ -f "$SCRIPT_AFTER_MAKE_TEST" ] ; then
    . $SCRIPT_AFTER_MAKE_TEST
  fi
  if [ -f "$SCRIPT_AFTER_MAKE_TEST_VERSIONED" ] ; then
    . $SCRIPT_AFTER_MAKE_TEST_VERSIONED
  fi
  echo ::endgroup::
fi

