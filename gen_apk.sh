#!/bin/bash

## test ok on cygwin && Mac OS X

set -e
set -x

pwd=$(pwd)
echo "pwd=$pwd" 

## for sed
export LC_COLLATE='C'
export LC_CTYPE='C'

svn='svn'
svnusername="jenkins"
svnpassword="jenkins"

sed='sed'
ant='ant'
android='android'
basepath=$(cd `dirname $0`;pwd)
xxtea="${basepath}/xxtea"
upload="bash ${basepath}/upload.sh"
set_config_kv="bash ${basepath}/set_config_kv.sh"
update_config_lua="bash ${basepath}/update_config_lua.sh"

aloss=${aloss-'aliyuncli oss'}
ossmfsn=${ossmfsn-'oss://mfsn-sc-patch-oss'}
ACT_OSS_ROOT=${ACT_OSS_ROOT-'tmp'}

uname=$(uname)
if [[ ${uname:0:6} == "Darwin" ]]; then
	sed='gsed'
elif [[ ${uname:0:6} == "CYGWIN" ]]; then
	xxtea="$${basepath}/xxtea.exe"
	android='android.bat'
else
	xxtea="${basepath}/xxtea.linux"
fi

# branch=$(git br|grep "^\*"|cut -d ' ' -f 2)
branch=$(${svn} info "${basepath}/.."|grep "^URL"|sed -e "s#^.*/##g" -e 's/[()\.]//g')

BUILD_NUMBER=${BUILD_NUMBER-'999'}
ACT_TARGET_PLATFORM=${ACT_TARGET_PLATFORM-'android_bili_test'}
ACT_USE_LOCAL_SERVERLIST=${ACT_USE_LOCAL_SERVERLIST-'false'}
ACT_ENABLE_UPDATE=${ACT_ENABLE_UPDATE-'true'}
ACT_IGNORE_SDK=${ACT_IGNORE_SDK-'false'}
ACT_SKIP_NEW_GUIDE=${ACT_SKIP_NEW_GUIDE-'false'}
ACT_BUILD_CONFIGURATION=${ACT_BUILD_CONFIGURATION-'Debug'}
ACT_LUA_DEBUG_OUT=${ACT_LUA_DEBUG_OUT-'2'}
if [[ $1 == "release" ]]; then
	ACT_BUILD_CONFIGURATION='Release'
fi
if [[ ${ACT_UPLOAD_FTP} == '' ]]; then
	ACT_UPLOAD_FTP="cn@192.168.10.131:share/mfsn/manual_${branch}=http://192.168.10.131:8008/share/mfsn/manual_${branch}"
fi

if [[ ! -f "build_history/${ACT_TARGET_PLATFORM}.version" ]]; then
	cp "build_history/template.version" "build_history/${ACT_TARGET_PLATFORM}.version"
	${svn} add "build_history/${ACT_TARGET_PLATFORM}.version"
fi

VERSION1=$(awk -F '=' '{print $2}' build_history/${ACT_TARGET_PLATFORM}.version | cut -d '.' -f 1)
VERSION2=$(awk -F '.' '{print $2}' build_history/${ACT_TARGET_PLATFORM}.version)
VERSION3=$(awk -F '.' '{print $3}' build_history/${ACT_TARGET_PLATFORM}.version)
VERSION1=${VERSION1-1}
VERSION2=${VERSION2-0}
if [ ${VERSION3} == '' ] || [ ${ACT_CLEAN_VERSION3} == 'true' ]; then
	VERSION3=0
fi
if [[ ${ACT_INCREASE_VERSION1} == 'true' ]]; then
	VERSION1=$((VERSION1+1))
fi
if [[ ${ACT_INCREASE_VERSION2} == 'true' ]]; then
	VERSION2=$((VERSION2+1))
fi
if [[ ${ACT_INCREASE_VERSION3} == 'true' ]]; then
	VERSION3=$((VERSION3+1))
fi
GEN_VERSION="${VERSION1}.${VERSION2}.${VERSION3}"
svnhead=$(${svn} info "." | grep "Last Changed Rev:" | sed -e "s/.*: //")
echo "$svnhead=${GEN_VERSION}"
echo "$svnhead=${GEN_VERSION}" > "build_history/${ACT_TARGET_PLATFORM}.version"
${svn} ci "build_history/${ACT_TARGET_PLATFORM}.version" --username "${svnusername}" --password "${svnpassword}" --no-auth-cache -m "auto update build_history/${ACT_TARGET_PLATFORM}.version to $svnhead=${GEN_VERSION}"

echo -e " 
====== Jenkins param ======
BUILD_NUMBER=${BUILD_NUMBER-'999'}
ACT_TARGET_PLATFORM=${ACT_TARGET_PLATFORM-'android_bili'}
ACT_USE_LOCAL_SERVERLIST=${ACT_USE_LOCAL_SERVERLIST-'false'}
ACT_ENABLE_UPDATE=${ACT_ENABLE_UPDATE-'true'}
ACT_IGNORE_SDK=${ACT_IGNORE_SDK-'false'}
ACT_SKIP_NEW_GUIDE=${ACT_SKIP_NEW_GUIDE-'false'}
ACT_BUILD_CONFIGURATION=${ACT_BUILD_CONFIGURATION-'Debug'}
ACT_LUA_DEBUG_OUT=${ACT_LUA_DEBUG_OUT-'2'}
====== Jenkins param end ======"

# svnhead=$(grep "^SVN_VERSION" src/config.lua | cut -d "\"" -f 2)
if [[ ${ACT_MERGE_VERSION/*@/} != '' ]]; then
	mergeversion=$(${svn} info "${ACT_MERGE_VERSION}" | grep "Last Changed Rev:" | $sed -e "s/.*: //")
	mergebranch=${ACT_MERGE_VERSION/*\//}
	mergebranch=${mergebranch/@*/}
fi

if [[ ${ACT_BUILD_TYPE} == 'GEN_UPDATE' ]];then
	echo 'gen GEN_UPDATE'
    exit 0
fi

export LANG=en_US.UTF-8

mkdir -p "apks/${ACT_TARGET_PLATFORM}"


# cocosbuild(){
# 	cocos compile -p android -m $(tr '[A-Z]' '[a-z]' <<< "${ACT_BUILD_CONFIGURATION}")
#     apkname="actgame_$1-${ACT_BUILD_CONFIGURATION}-${GEN_VERSION}-r${svnhead}-$(date '+%Y%m%d_%H%M%S').apk"
# 	mv "./bin/ActGame-${ACT_BUILD_CONFIGURATION}.apk" "apks/${GEN_VERSION}/$apkname"
# 	$upload ${apkname}
# }

native_build(){
	LOCAL_PATH=$(pwd)
	# echo "$LOCAL_PATH"
	export NDK_MODULE_PATH="${LOCAL_PATH}:${LOCAL_PATH}/../../cocos2d-x:${LOCAL_PATH}/../../cocos2d-x/cocos/:${LOCAL_PATH}/../../cocos2d-x/external:${LOCAL_PATH}/../../cocos2d-x/cocos/scripting"
	export NDK_TOOLCHAIN_VERSION=4.9
	if [[ ${ACT_BUILD_CONFIGURATION} == "Release" ]]; then
	    export NDK_DEBUG=0 
	else
	    export NDK_DEBUG=1
	fi
	rm -rfv obj/local/*/*.a
	${NDK_ROOT}/ndk-build -j4
}

ant_build(){
	# find assets "*.luac" -delete
	## release
	# if [[ ${ACT_BUILD_CONFIGURATION} == "Release" ]]; then
		## compile lua to luac
		# find assets -name "*.lua" -exec luajit -b "{}" "{}c" \; -exec rm "{}" \; -exec echo -e "{} => {}c" \;
	# fi

	## ant package
	which $ant
	$ant clean
	$ant $(tr '[A-Z]' '[a-z]' <<< ${ACT_BUILD_CONFIGURATION}) ## 2>&1 | tee ant.out
}

################################ main ################################

pushd frameworks/runtime-src/proj.${ACT_TARGET_PLATFORM/_test*/}

## build native code 
native_build

## 拷贝 res, src 到 assets 目录
mkdir -p assets
rm -rf ./assets/*
echo "copy src ..."
cp ../../../main.* "./assets/"
cp -rf ../../../src "./assets/"
echo "copy res ..."
cp -rf ../res_${branch}/res "./assets/"
echo "copy biliRes ..."
cp -rf "sdkResources/biliRes/" "./assets/"
## use json format of spine on android
find assets -name "*.lua" -exec $sed -e "s/\.kksp/.json/g" -i "{}" \;
rm -rf "assets/res/spine/*.kksp"

## 更新 `src.cfg/config.${ACT_TARGET_PLATFORM}.lua` 中的 `VERSION`, `SVN_VERSION` 等动态参数
echo "updatting src.cfg/config.${ACT_TARGET_PLATFORM}.lua ..."
$update_config_lua "../../../src.cfg/config.${ACT_TARGET_PLATFORM}.lua" "ACT_TARGET_PLATFORM=${ACT_TARGET_PLATFORM}"
${svn} ci --username "${svnusername}" --password "${svnpassword}" --no-auth-cache "../../../src.cfg" -m "auto update src.cfg/config.${ACT_TARGET_PLATFORM}.lua"

## 拷贝 `src.cfg/config.{platform}.lua` 到 `proj.{platform}/assets/src/config.lua`
echo "copy src.cfg/config.${ACT_TARGET_PLATFORM}.lua ..."
cp -rf "../../../src.cfg/config.${ACT_TARGET_PLATFORM}.lua" "./assets/src/config.lua"
cat "./assets/src/config.lua"
## 更新 `AndroidManifest.xml` 中的 `versionCode`, `versionName` 等动态参数
echo "updatting AndroidManifest.xml ..."
# $sed -e 's#package="[^"]*$#package="'${ACT_PACKAGE_NAME}'\"#g' -i 'AndroidManifest.xml'
versionCode=$(grep "android:versionCode" 'AndroidManifest.xml' | $sed -e 's#.*android:versionCode=\"\(.*\)\"$#\1#g')
versionCode=$((versionCode+1))
$sed -e 's#android:versionCode=.*$#android:versionCode="'${versionCode}'\"#g' -i 'AndroidManifest.xml'
$sed -e 's#android:versionName=.*$#android:versionName="'${GEN_VERSION}'\"#g' -i 'AndroidManifest.xml'
${svn} ci --username "${svnusername}" --password "${svnpassword}" --no-auth-cache 'AndroidManifest.xml' -m "auto update versionCode to ${versionCode} in AndroidManifest.xml"
## app name
# $sed -e 's#\(name="app_name">\).*<#\1'${ACT_APP_NAME}'<#g' -i 'res/values/strings.xml'

## 更新 local.properties
echo "updatting android local.properties ..."
target_android="android-19"
$android update project -p . --subprojects --target ${target_android}
$android update project -p ../../cocos2d-x/cocos/platform/android/java --subprojects --target ${target_android}
## sdk lianyun
$android update project -p ../SdkLibrary/lianyun/bsgamesdk_android_library --subprojects --target ${target_android}
$android update project -p ../SdkLibrary/lianyun/BSGameSdkProxy_Android_bilibili_Library --subprojects --target ${target_android}
$android update project -p ../SdkLibrary/lianyun/BSGameSdkProxy_Android_Library --subprojects --target ${target_android}

## sdk bili
$android update project -p ../SdkLibrary/bsgamesdk_android_library --subprojects --target ${target_android}

## sdk sharejoy
$android update project -p ../SdkLibrary/bsgamesdk_android_sharejoy --subprojects --target ${target_android}

## sdk plugins
$android update project -p ../../cocos2d-x/plugin/plugins/umeng/push/android --subprojects --target ${target_android}
$android update project -p ../../cocos2d-x/plugin/plugins/xfyun/android --subprojects --target ${target_android}
echo "updatting sdk local.properties ok"

## 加密 `assets/(src|res)`
echo "encode src && res ..."
$xxtea assets/src
$xxtea assets/res

mkdir -p apks
rm -f apks/*.apk
## 打包, 签名
ant_build

## 重命名为 mfsn-{platform}-{version}-{build_number}.apk
apkname="mfsn-${ACT_TARGET_PLATFORM}-${GEN_VERSION}-${versionCode}-${svnhead}-${BUILD_NUMBER}.apk"
mv "./bin/ActGame-$(tr '[A-Z]' '[a-z]' <<< "${ACT_BUILD_CONFIGURATION}").apk" "apks/${apkname}"
pushd "apks"
	$upload "${apkname}"
	## 上传阿里云
	if [[ ${AUTO_UPLOAD_OSS} == "true" ]]; then
		echo "upload ${apkname} to aliyun oss ..."
		${aloss} Put "${apkname}" "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${apkname}"
		echo "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${apkname}"
		echo "http://line1.patch.madoka.biligame.net/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${apkname}"
	fi
popd

## 记录 `VERSION`, `SVN_VERSION` 到 `version_history/{platform}.verson` 和 `version_history/{platform}.version_history` 中
echo "${ACT_TARGET_PLATFORM} ${svnhead}=${GEN_VERSION}"
mkdir -p "../../../build_history"
pushd "../../../build_history/"
	if [[ ! -f "${ACT_TARGET_PLATFORM}.update_history" ]]; then
		echo "${svnhead}=${GEN_VERSION}" > "${ACT_TARGET_PLATFORM}.update_history"
		${svn} add "${ACT_TARGET_PLATFORM}.update_history"
	else
		echo "${svnhead}=${GEN_VERSION}" >> "${ACT_TARGET_PLATFORM}.update_history"
	fi
	$upload "${ACT_TARGET_PLATFORM}.version.lua" "version.lua"
	${svn} ci "${ACT_TARGET_PLATFORM}.update_history" --username "${svnusername}" --password "${svnpassword}" --no-auth-cache -m "auto update build_history/${ACT_TARGET_PLATFORM}.update_history"
	# ## 上传阿里云
	# if [[ ${AUTO_UPLOAD_OSS} == "true" ]]; then
	# 	echo "upload ${ACT_TARGET_PLATFORM}.version.lua to aliyun oss ..."
	# 	${aloss} Put "${ACT_TARGET_PLATFORM}.version.lua" "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	# 	${aloss} Cat "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	# 	echo "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	# 	echo "http://line1.patch.madoka.biligame.net/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	# fi
	cat "${ACT_TARGET_PLATFORM}.version.lua"
popd ##"../../../build_history/"

## 更新内网下载页面
mkdir -p ./qr
echo "generate qr img ..."
qrurl="${ACT_UPLOAD_FTP/*=}/${ACT_TARGET_PLATFORM}/${apkname}"
qrencode $qrurl -t png -o "qr/${apkname}.png"
scp "qr/${apkname}.png" "${ACT_UPLOAD_FTP/=*}/${ACT_TARGET_PLATFORM}/qr/"
if [[ ! -f "../html/dl-${ACT_TARGET_PLATFORM}.html" ]]; then
	echo "update index page ..."
	cp "../html/dl-template.html" "../html/dl-${ACT_TARGET_PLATFORM}.html"
	$sed '/<!--apkdownloadpage-->/a\    <a href="'${ACT_UPLOAD_FTP/*=}$'/dl-'${ACT_TARGET_PLATFORM}$'.html"><h2>'"${branch}"':'${ACT_TARGET_PLATFORM}$'</h2></a><br/>' -i "../html/index.html"
	${svn} ci "../html/index.html" --username "${svnusername}" --password "${svnpassword}" --no-auth-cache -m "auto add dl-${ACT_TARGET_PLATFORM}.html to html/index.html"
	scp "../html/index.html" "${ACT_UPLOAD_FTP/:*}:" ## home page
fi
echo "update download page ..."
$sed '/<!-- apkbegin -->/a\'$'    <a href="'"${ACT_TARGET_PLATFORM}"$'/'"${apkname}"$'"><img src="'${ACT_TARGET_PLATFORM}$'/qr/'${apkname}$'.png" title="小圆'${ACT_TARGET_PLATFORM}$'"><br/>'${apkname}$'</a></br>'"$(date)"$'<br/><br/>' -i "../html/dl-${ACT_TARGET_PLATFORM}.html"
scp "../html/dl-${ACT_TARGET_PLATFORM}.html" "${ACT_UPLOAD_FTP/=*}"

popd ## frameworks/runtime-src/proj.android

