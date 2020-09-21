#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [ $# -ne 3 ]; then
    echo "usage) $0 [patch|reset] [RAY_HOME] [WHEEL]"
    exit 1
fi

OP=$1
RAY_HOME=$2
WHEEL=$3

RAY_UID=1000
RAY_GID=100

SED_INPLACE="sed -i"
uname | grep Darwin > /dev/null
if [ $? -eq 0 ]; then
    SED_INPLACE="sed -i .bak"
fi

if [ "$OP" == "patch" ]; then
    # patch wheel url
    echo "$WHEEL" | grep ^http > /dev/null
    if [ $? -ne 0 ]; then
        # path is given
        $SED_INPLACE "s|set -x|set -x; set -e|g" $RAY_HOME/build-docker.sh
        $SED_INPLACE "s|^WHEEL=.*|WHEEL=$WHEEL|g" $RAY_HOME/build-docker.sh
        $SED_INPLACE "s|wget.*||g" $RAY_HOME/build-docker.sh
    else
        # url is given
        $SED_INPLACE "s|^WHEEL_URL=.*|WHEEL_URL=\"$WHEEL\"|g" $RAY_HOME/build-docker.sh
    fi

    # build ray-ml
    $SED_INPLACE "s/\"ray-deps\" \"ray\"/\"ray-deps\" \"ray\" \"ray-ml\"/g" $RAY_HOME/build-docker.sh

    # patch PATH
    $SED_INPLACE "s/\/root/\/home\/ray/g" ${RAY_HOME}/docker/base-deps/Dockerfile

    # patch PATH in profile
    $SED_INPLACE "s/ \/etc\/profile.d\/conda.sh/\> \/home\/ray\/.bash_profile/g" ${RAY_HOME}/docker/base-deps/Dockerfile

    # patch kubectl installation section
    $SED_INPLACE "s/apt-key add/sudo apt-key add/g" ${RAY_HOME}/docker/base-deps/Dockerfile
    $SED_INPLACE "s/touch \/etc/sudo touch \/etc/g" ${RAY_HOME}/docker/base-deps/Dockerfile
    $SED_INPLACE "s/tee -a \/etc/sudo tee -a \/etc/g" ${RAY_HOME}/docker/base-deps/Dockerfile

    # patch apt-get
    $SED_INPLACE "s/apt-get/sudo apt-get/g" ${RAY_HOME}/docker/base-deps/Dockerfile
    $SED_INPLACE "s/rm -rf \/var/sudo rm -rf \/var/g" ${RAY_HOME}/docker/base-deps/Dockerfile
    $SED_INPLACE "s/apt-get/sudo apt-get/g" ${RAY_HOME}/docker/ray-ml/Dockerfile

    # patch rm
    $SED_INPLACE "s/ rm / sudo rm /g" ${RAY_HOME}/docker/ray-deps/Dockerfile
    $SED_INPLACE "s/ rm / sudo rm /g" ${RAY_HOME}/docker/ray/Dockerfile
    $SED_INPLACE "s/ rm / sudo rm /g" ${RAY_HOME}/docker/ray-ml/Dockerfile

    # Add ray user & install sudo
    # lines until 'ARG DEBIAN_FRONTNED ...'
    #
    # install tzdata here to initialize tzdata in non-interactive mode.
    # otherwise, tzdata will be installed as a transitive dependency later and show keyboard prompt
    cat $RAY_HOME/docker/base-deps/Dockerfile | sed '/ARG DEBIAN/q' > /tmp/ray_tmp_docker
    cat <<EOF >> /tmp/ray_tmp_docker
RUN apt-get update -y && apt-get install -y sudo tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
RUN useradd -ms /bin/bash -d /home/ray ray --uid $RAY_UID --gid $RAY_GID \
    && usermod -aG sudo ray \
    && echo 'ray ALL=NOPASSWD: ALL' >> /etc/sudoers
USER 1000
ENV HOME=/home/ray
EOF

    # lines after 'ARG DEBIAN_FRONTNED ...'
    cat $RAY_HOME/docker/base-deps/Dockerfile | sed '1,/ARG DEBIAN/d' >> /tmp/ray_tmp_docker
    mv /tmp/ray_tmp_docker $RAY_HOME/docker/base-deps/Dockerfile

    # in case of py38, atari-py package installation fails without few os packages
    $SED_INPLACE "s/RUN \$HOME/RUN sudo apt-get update \&\& sudo apt-get install -y g++ cmake zlib1g-dev \&\& \$HOME/g" ${RAY_HOME}/docker/ray-deps/Dockerfile
    $SED_INPLACE "s/RUN \$HOME/RUN sudo apt-get update \&\& sudo apt-get install -y g++ cmake zlib1g-dev \&\& \$HOME/g" ${RAY_HOME}/docker/ray/Dockerfile
    $SED_INPLACE "s/\(\&\& sudo rm.*\)/\1 \&\& sudo apt-get autoremove -y cmake g++ \&\& sudo rm -rf \/var\/lib\/apt\/lists\/\* \&\& sudo apt-get clean/g" ${RAY_HOME}/docker/ray-deps/Dockerfile
    $SED_INPLACE "s/\(\&\& sudo rm.*\)/    \1 \&\& sudo apt-get autoremove -y cmake g++ \&\& sudo rm -rf \/var\/lib\/apt\/lists\/\* \&\& sudo apt-get clean/g" ${RAY_HOME}/docker/ray/Dockerfile

elif [ "$OP" == "reset" ]; then
    git checkout ${RAY_HOME}/docker/ray/Dockerfile
    git checkout ${RAY_HOME}/docker/ray-deps/Dockerfile
    git checkout ${RAY_HOME}/docker/base-deps/Dockerfile
    git checkout ${RAY_HOME}/docker/ray-ml/Dockerfile
    git checkout ${RAY_HOME}/build-docker.sh
else
    echo "Invalid operation $OP"
    exit 1
fi

