#!/bin/bash

if [[ $TRAVIS_OS_NAME = 'osx' ]]; then
  # install macOS prerequistes
  :
elif [[ $TRAVIS_OS_NAME = 'linux' ]]; then
  export SWIFT_VERSION=swift-5.3-RELEASE   
  wget https://swift.org/builds/swift-5.3-release/ubuntu1804/${SWIFT_VERSION}/${SWIFT_VERSION}-ubuntu18.04.tar.gz
  tar xzf ${SWIFT_VERSION}-ubuntu18.04.tar.gz
  export PATH="${PWD}/${SWIFT_VERSION}-ubuntu18.04/usr/bin:${PATH}"
fi
