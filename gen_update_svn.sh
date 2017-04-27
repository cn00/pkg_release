#!/bin/bash

# set -e
set -x

pwd=$(pwd)
echo "pwd=$pwd" 

export LC_ALL=C
export LANG=en_US.UTF-8

if [[ ${BUILD_NUMBER} == '' ]]; then
	BUILD_NUMBER='nil'
fi

svn='svn'
svnusername="jenkins"
svnpassword="jenkins"

sed='gsed'
basepath=$(cd `dirname $0`;pwd)
xxtea="${basepath}/xxtea"
set_config_kv="${basepath}/set_config_kv.sh"
update_config_lua="${basepath}/update_config_lua.sh"
upload="${basepath}/upload.sh"

aloss=${aloss-'aliyuncli oss'}
ossmfsn=${ossmfsn-'oss://mfsn-sc-patch-oss'}
ACT_OSS_ROOT=${ACT_OSS_ROOT-'tmp'}

uname=$(uname)
if [[ ${uname:0:6} == "Darwin" ]]; then
	sed='gsed'
elif [[ ${uname:0:6} == "CYGWIN" ]]; then
	xxtea="${basepath}/xxtea.exe"
	android='android.bat'
else
	xxtea="${basepath}/xxtea.linux"
fi

VERSION1=$(awk -F '=' '{print $2}' build_history/${ACT_TARGET_PLATFORM}.version | cut -d '.' -f 1)
VERSION2=$(awk -F '.' '{print $2}' build_history/${ACT_TARGET_PLATFORM}.version)
VERSION3=$(awk -F '.' '{print $3}' build_history/${ACT_TARGET_PLATFORM}.version)
if [[ ${VERSION1} == '' ]]; then
	VERSION1=0
fi
if [[ ${VERSION2} == '' ]]; then
	VERSION2=0
fi
if [[ ${VERSION3} == '' ]]; then
	VERSION3=0
fi
GEN_VERSION="${VERSION1}.${VERSION2}.$((VERSION3+1))"

# svnhead=$(grep "^SVN_VERSION" src/config.lua | cut -d "\"" -f 2)
svnhead=$(${svn} info "${basepath}/.."| grep 'Last Changed Rev: ' | cut -d ':' -f 2 | cut -d ' ' -f 2)
echo "$svnhead=${GEN_VERSION}"
echo "$svnhead=${GEN_VERSION}" > "build_history/${ACT_TARGET_PLATFORM}.version"

# branch=$(git svn info|grep "^URL"|sed -e "s#^.*/##g")
branch=$(${svn} info "${basepath}/.."|grep "^URL"|sed -e "s#^.*/##g" -e 's/[()\.]//g')
echo branch=$branch
# ${svn} ci -m "update version ${version}"

## BASE --> diff_version_n --> encode --> update.BASE-version_n.zip
## BASE [1000] --> update.1000-1090.zip
## 	update_1 [1010] --> update.1090-1010.zip
## 		update_2 [1020] --> update.1090-1020.zip
## 			update_3 [1030] --> update.1090-1030.zip
## 				update_n --> update.1090-n.zip
## HEAD [1090] --> dev
mkdir -p "update.${ACT_TARGET_PLATFORM}/${GEN_VERSION}"
rm   -rf "update.${ACT_TARGET_PLATFORM}/${GEN_VERSION}"
previouszip=''
previous_svn=''
for v in $(cat build_history/${ACT_TARGET_PLATFORM}.update_history | sed -e '/^#.*/d' -e 's/=.*$//g' | sort -u | sed -n '1!G;h;$p');do
	echo -e " ========= $v ========= "
	if [[ $v -lt ${svnhead} ]]; then
		package="update.${ACT_TARGET_PLATFORM}/${GEN_VERSION}/${svnhead}-$v.zip"
		if [[ $previous_svn == '' ]]; then
			previous_svn=$svnhead
		fi
		if [[ $previouszip != '' ]]; then
			echo "use previouszip=${previouszip}"
			cp $previouszip $package
		fi
		# src
		# 7z u $package `${svn} log src -v -r$v:${svnhead} | grep 'Code/c_branches/publish/src/' | sed -e 's!^.*Code/c_branches/publish/!!g'| sort | uniq -u `
		srclist=`${svn} log src -v -r${previous_svn}:${v} | grep -e '^\s*[AM].*/src/' | sed -e "s#^ *[AM] *.*/src/#src/#g" -e 's# *(from .*)$##g' -e '/src\/config.lua/d' | sort -u` 
		srclist="${srclist} src/config.lua"

		for f in $srclist;do 
			# echo $f
			mv "$f" "${f}.bak"
			$xxtea "${f}.bak" "${f}"
			7z u "$package" "$f"
			mv "${f}.bak" "${f}"
		done
		echo "gen src ok"

		## res
		${svn} log res -v -r${previous_svn}:${v} | grep -e '^\s*[AM].*/res/' | sed -e "s#^ *[AM] *.*/res/#res/#g" -e 's#(from .*)$##g' | sort -u > ".reslist"
		images=$(cat .reslist | grep -e ".*.png" -e ".*.jpg")	
		others=$(cat .reslist | sed -e "/.*.png/d" -e "/.*.jpg/d")
		# echo $images
		for f in $images; do
			cp "$f" "${f}.bak"
			# pngquant --force -o "$f" -- "$f"
			## encode img
			$xxtea "${f}"
			7z u "$package" "$f"
			## decode img
			$xxtea "${f}"
			mv -f "${f}" "frameworks/runtime-src/res_${branch}/${f}"
			mv "${f}.bak" "${f}"
		done
		## others
		# echo $others
		if [[ ${#others} > 0 ]]; then
			for f in $others; do
				if [[ -f $f ]]; then
					echo "others:$f"
					7z u "$package" "$f"
				fi
			done
		fi
		previouszip=$package
		previous_svn=$v
		echo "gen res ok"
	else
		echo "no more updates"
	fi

done

echo " ======================= gen all update packages ok ======================= "

## backup config.lua
configlua='src/config.lua'
mv -f "$configlua"  "src/config.lua.origin.bak"
echo "update_config_lua ..."
$update_config_lua "src.cfg/config.${ACT_TARGET_PLATFORM}.lua"
cp -f "src.cfg/config.${ACT_TARGET_PLATFORM}.lua" "src/config.lua"
cat $configlua
${svn} ci --username "${svnusername}" --password "${svnpassword}" --no-auth-cache "src.cfg" -m "auto update src.cfg/config.${ACT_TARGET_PLATFORM}.lua ${GEN_VERSION}"
## encode configlua
$xxtea $configlua
echo "add $configlua to zips"
for pkg in $(find update.${ACT_TARGET_PLATFORM}/${GEN_VERSION}/*.zip); do
 	7z a $pkg $configlua
done 
mv "src/config.lua.origin.bak" "src/config.lua"

## 
echo "uploading packages update.${ACT_TARGET_PLATFORM}/${GEN_VERSION} ..."
scp -r "update.${ACT_TARGET_PLATFORM}/${GEN_VERSION}" "${ACT_UPLOAD_FTP/=*}/${ACT_TARGET_PLATFORM}"

## 记录 `VERSION`, `SVN_VERSION` 到 `version_history/{platform}.verson` 和 `version_history/{platform}.version_history` 中
mkdir -p "build_history"
echo "$svnhead=${GEN_VERSION}"
echo "$svnhead=${GEN_VERSION}" >> "build_history/${ACT_TARGET_PLATFORM}.update_history"
${svn} ci --username "${svnusername}" --password "${svnpassword}" --no-auth-cache "build_history" -m "auto update build_history/${ACT_TARGET_PLATFORM} ${GEN_VERSION}"
pushd "build_history/"
$upload "${ACT_TARGET_PLATFORM}.version.lua" "version.lua"
popd
# scp  "build_history/${ACT_TARGET_PLATFORM}.version.lua" "${ACT_UPLOAD_FTP/=*}/${ACT_TARGET_PLATFORM}/"

if [[ ${AUTO_UPLOAD_OSS} == "true" ]]; then
	echo "upload update.${ACT_TARGET_PLATFORM}/${GEN_VERSION} to aliyun oss ..."
	for f in $(find update.${ACT_TARGET_PLATFORM}/${GEN_VERSION}/*.zip); do
		${aloss} Put "${f}" "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${GEN_VERSION}/"
	done
	# ${aloss} Put "build_history/${ACT_TARGET_PLATFORM}.version.lua" "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
fi
