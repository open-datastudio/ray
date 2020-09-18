#!/bin/bash
# Custom builder script for Skaffold
# https://skaffold.dev/docs/pipeline-stages/builders/custom/
#

set -x
set -e
pwd

PYTHON_VERSION=$1
SHORT_VER=`echo $PYTHON_VERSION | sed "s/\([0-9]*\)[.]\([0-9]*\)[.][0-9]*/\1\2/g"`

# true to build .whl from source (will take about 3 hours).
# false to use pre-built whl file from http(s) url.
BUILD_WHEEL=${BUILD_WHEEL:-false}

if [ "$BUILD_WHEEL" == "true" ]; then
    if [ ! -d ".whl" ]; then # check if already built.
        # Uncomment followings to build wheel for only single python version.
        #sed -ie "/^PYTHONS=/,+2d" python/build-wheel-manylinux1.sh
        #sed -ie "/^chmod/a PYTHONS=\(\"cp37-cp37m\"\)" python/build-wheel-manylinux1.sh
        #git config user.name "build"
        #git config user.email "ci@build.com"
        #git commit python/build-wheel-manylinux1.sh -m "update"
        #cat python/build-wheel-manylinux1.sh

        # current commit
        COMMIT=`git rev-parse HEAD`

        docker run \
            -e TRAVIS_COMMIT=$COMMIT \
            --rm -i \
            -w /ray \
            -v `pwd`:/ray \
            rayproject/arrow_linux_x86_64_base:python-3.8.0 \
            /ray/python/build-wheel-manylinux1.sh
    fi

    WHEEL=`ls .whl/*-cp$SHORT_VER-*`
else
    if [ "$SHORT_VER" == "36" ]; then
        WHEEL="https://s3-us-west-2.amazonaws.com/ray-wheels/latest/ray-1.1.0.dev0-cp36-cp36m-manylinux1_x86_64.whl"
    elif [ "$SHORT_VER" == "37" ]; then
        WHEEL="https://s3-us-west-2.amazonaws.com/ray-wheels/latest/ray-1.1.0.dev0-cp37-cp37m-manylinux1_x86_64.whl"
    elif [ "$SHORT_VER" == "38" ]; then
        WHEEL="https://s3-us-west-2.amazonaws.com/ray-wheels/latest/ray-1.1.0.dev0-cp38-cp38-manylinux1_x86_64.whl"
    fi
fi

# apply non-root docker image patch
./.staroid/ray_patch.sh reset . .
./.staroid/ray_patch.sh patch . $WHEEL

# print patched files
git diff

cat docker/ray/Dockerfile
cat docker/ray-deps/Dockerfile

# build docker image
./build-docker.sh --no-cache-build --gpu --python-version $PYTHON_VERSION

# print images
docker tag rayproject/ray:latest-gpu $IMAGE
docker images

if $PUSH_IMAGE; then
    docker push $IMAGE
fi
