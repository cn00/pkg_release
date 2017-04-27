#!/bin/bash

# $1 HASH-HEAD1
# $2 HASH-HEAD2

export LC_ALL=C

lang=$LANG
export LANG=en_US.UTF-8

targetdir='src res'
targetpkg='update.zip'
lastversion=`cat .lastversion`
fileList=''

mv update.zip update.$lastversion.zip

if   [[ $# < 1 ]]; then
	fileList=`git st $targetdir | grep -e 'modified' | sed -e 's!^.*src!src!g' -e 's!^.*\s*res!res!g' | sort | uniq -u `
elif [[ $# -eq 1 ]]; then
	fileList=`git diff --name-status $1 $targetdir | grep -e '^M\s*src' -e '^A\s*src' | sed -e 's!^A.*src/!src/!g'| sort | uniq -u `
elif [[ $# -eq 2 ]]; then
	fileList=`git diff --name-status $1 $2  $targetdir | grep -e '^M\s*src' -e '^A\s*src' | sed -e 's!^A.*src/!src/!g'| sort | uniq -u `
fi

echo $fileList

7z u $targetpkg $fileList

echo $1 > .lastversion

export LANG=$lang

# php -S 0.0.0.0:8000 -t .
