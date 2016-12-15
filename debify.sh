#!/bin/bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

if [ ! -d /debs ]
then
    echo "Mount your Debian package directory to /debs."
    exit 1
fi

if [ ! -d /debs/incoming ] || [ ! "$(ls -A /debs/incoming/)" ]
then
    echo "ensure there are new packages in /debs/incoming."
    exit 1
fi

APTLY_REPO_NAME=debify

if ! aptly repo create \
    -component="$APTLY_COMPONENT" \
    -distribution="$APTLY_DISTRIBUTION" \
    $APTLY_REPO_NAME 2>&1 | tee out.log; then

    grep "already exists" out.log || exit 1
fi

echo "--- adding packages: ---"
aptly repo add -remove-files=true $APTLY_REPO_NAME /debs/incoming/

echo "---"
echo "current contents:"
aptly repo show $APTLY_REPO_NAME
echo "---"

if [ ! -z "$GPG_PASSPHRASE" ]
then
    passphrase="$GPG_PASSPHRASE"
elif [ ! -z "$GPG_PASSPHRASE_FILE" ]
then
    passphrase=$(<$GPG_PASSPHRASE_FILE)
fi

aptly publish repo \
    -architectures="$APTLY_ARCHITECTURES" \
    -passphrase="$passphrase" \
    -batch \
    $APTLY_REPO_NAME \
|| echo " --- updating instead... --- " && aptly publish update \
    -architectures="$APTLY_ARCHITECTURES" \
    -passphrase="$passphrase" \
    -batch \
    "$APTLY_DISTRIBUTION"

if [ ! -z "$KEYSERVER" ] && [ ! -z "$URI" ]
then
    release_sig_path=$(find /debs/public/dists -name Release.gpg | head -1)
    gpg_key_id=$(gpg --list-packets $release_sig_path | grep -oP "(?<=keyid ).+")

    if [[ "$URI" != */ ]]; then
        URI="${URI}/"
    fi

    cat > /debs/public/go <<-END
#!/bin/sh
##
## How to install this repository:
##   curl -sSL ${URI}go | sh
## OR
##   wget -qO- ${URI}go | sh
##

set -e
END

    case "$URI" in
        https://*)
            cat >> /debs/public/go <<-END
install_https() {
    if [ ! -e /usr/lib/apt/methods/https ]; then
        apt-get update && apt-get install -y apt-transport-https
    fi
}
install_https
END
    esac

    cat >> /debs/public/go <<-END
do_install() {
    apt-key adv --keyserver $KEYSERVER --recv-keys $gpg_key_id
    echo "deb $URI $APTLY_DISTRIBUTION $APTLY_COMPONENT" >> /etc/apt/sources.list
    apt-get update
}
do_install
END
cp /debs/public/go /debs/install_testing
fi
