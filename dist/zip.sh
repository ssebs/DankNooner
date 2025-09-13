#!/bin/bash

DIRS=`find . -type d -name "dank-nooner*" | xargs`
echo $DIRS

for d in $DIRS; do
    cd $d
    zip -r $d.zip ./
    mv $d.zip ../
    cd ../
done
