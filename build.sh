#!/bin/bash
VER=$1
REV=$2
set -e

git clone git://github.com/esl/MongooseIM.git mongooseim
cd mongooseim
git checkout ${VER}

# sudo adduser --quiet --system --shell /bin/sh --group mongooseim
cp -r ../debian debian
cp ../Makefile .
sed -i "s#@VER@#${VER}-${REV}#" debian/changelog


# sudo apt-get update
# sudo apt-get install esl-erlang=1:17.5.3 libexpat1-dev -y
# sudo apt-get install libexpat1-dev -y


cd ..
#dpkg-source --before-build mongooseim
cd mongooseim
fakeroot debian/rules clean
dh_testdir
make configure full
make rel -j1
fakeroot debian/rules binary

#HOSTNAME=`hostname`
#mv ../mongooseim_*.deb ../mongooseim_${VER}-${REV}~${HOSTNAME}.deb
#upload ../mongooseim_${VER}-${REV}~${HOSTNAME}.deb

