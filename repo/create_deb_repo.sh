#!/bin/bash
TOPDIR=$(cd $(dirname "$0") && pwd)
old_path=`pwd`

cd $TOPDIR/
dpkg-scanpackages debs/ |gzip > debs/Packages.gz
rm -rf /var/www/debs
cp -rf $TOPDIR/debs /var/www/

cd $old_path
