# !/bin/bash

set -e
set -x

## for sed
export LC_COLLATE='C'
export LC_CTYPE='C'

echo "pwd=" $(pwd)

svn='svn'
svnusername="jenkins"
svnpassword="jenkins"

sed='gsed'
basepath=$(cd `dirname $0`;pwd)
xxtea="${basepath}/xxtea"
upload="${basepath}/upload.sh"
set_config_kv="${basepath}/set_config_kv.sh"
update_config_lua="${basepath}/update_config_lua.sh"

aloss=${aloss-'aliyuncli oss'}
ossmfsn=${ossmfsn-'oss://mfsn-sc-patch-oss'}
ACT_OSS_ROOT=${ACT_OSS_ROOT-'tmp'}

# == it seemd that xctool can only catch single arch ==
#buildtool="xctool"
xcodeprojdir="."
buildtool="xcodebuild"
sdk=$(xcodebuild -showsdks | grep -e "^\siOS" | sed -e 's/^.*-sdk/-sdk/')
#archs="-arch armv7"
archs="-arch arm64 -arch armv7"

# branch=$(git br|grep "^\*"|cut -d ' ' -f 2)
branch=$(${svn} info "${basepath}/.."|grep "^URL"|sed -e "s#^.*/##g" -e 's/[()\.]//g')
echo branch=$branch

BUILD_NUMBER=${BUILD_NUMBER-'999'}
ACT_TARGET_PLATFORM=${ACT_TARGET_PLATFORM-'ios_bili_test'}
ACT_USE_LOCAL_SERVERLIST=${ACT_USE_LOCAL_SERVERLIST-'false'}
ACT_ENABLE_UPDATE=${ACT_ENABLE_UPDATE-'true'}
ACT_IGNORE_SDK=${ACT_IGNORE_SDK-'false'}
ACT_SKIP_NEW_GUIDE=${ACT_SKIP_NEW_GUIDE-'false'}
ACT_BUILD_CONFIGURATION=${ACT_BUILD_CONFIGURATION-'Debug'}
ACT_LUA_DEBUG_OUT=${ACT_LUA_DEBUG_OUT-'2'}
USE_LOCAL_SERVERLIST=${USE_LOCAL_SERVERLIST-'true'}
ACT_APP_NAME=${ACT_APP_NAME-'魔法少女小圆'}
ACT_PACKAGE_NAME=${ACT_PACKAGE_NAME-'com.bilibili.mfsnxy'}

if [[ $1 == "debug" ]]; then
	ACT_BUILD_CONFIGURATION='Debug'
fi
if [[ ${ACT_UPLOAD_FTP} == '' ]]; then
	ACT_UPLOAD_FTP="cn@192.168.10.131:share/mfsn/manual_${branch}=http://192.168.10.131:8008/share/mfsn/manual_${branch}"
fi

if [[ ${ACT_BUILD_CONFIGURATION} == 'Release' ]]; then
	ACT_IOS_CODE_SIGNE="68P6J27G77=iPhone Distribution: Wuhu Sharejoy network technology Co. Ltd=c849e683-9700-47fb-8382-a766cd66e30c" #发布证书
else
	# teamid=cer=profile
	ACT_IOS_CODE_SIGNE="68P6J27G77=iPhone Developer: Shuai Jiang=c849e683-9700-47fb-8382-a766cd66e30c" #调试的证书
fi

# ACT_IOS_CODE_SIGNE=${ACT_IOS_CODE_SIGNE/\#*}
DEVELOPMENT_TEAM=$(    echo ${ACT_IOS_CODE_SIGNE} | cut -d= -f1)
CODE_SIGN_IDENTITY=$(  echo ${ACT_IOS_CODE_SIGNE} | cut -d= -f2)
PROVISIONING_PROFILE=$(echo ${ACT_IOS_CODE_SIGNE} | cut -d= -f3)

if [[ ! -f build_history/${ACT_TARGET_PLATFORM}.version ]]; then
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

echo -e " ====== Jenkins param ======
ACT_BUILD_TYPE:${ACT_BUILD_TYPE}
ACT_TARGET_PLATFORM:${ACT_TARGET_PLATFORM}
GEN_VERSION:${GEN_VERSION}
ACT_BUILD_CONFIGURATION:${ACT_BUILD_CONFIGURATION}
ACT_UPLOAD_FTP:${ACT_UPLOAD_FTP}
DEVELOPMENT_TEAM:${DEVELOPMENT_TEAM}
CODE_SIGN_IDENTITY:${CODE_SIGN_IDENTITY}
PROVISIONING_PROFILE:${PROVISIONING_PROFILE}
====== Jenkins param end ======"

## config

pushd "frameworks/runtime-src/proj.ios_mac"

target="ActGame_${ACT_TARGET_PLATFORM/_test*/}"

alltargets=$(xcodebuild -list | grep ActGame_ | sort -u | sed -e "s/^        //g")

echo -e " ========== active targets ========== \n${target} \n\n"
echo -e " ========== available targets ========== \n${alltargets} \n\n"


################################ main ################################
# # > 更新 `ios/Info.${ACT_TARGET_PLATFORM}.plist` 中的 `CFBundleVersion`, `CFBundleShortVersionString` 等动态参数
echo "updatting Info.${ACT_TARGET_PLATFORM/_test*/}.plist ..."
infoplist="ios/Info.${ACT_TARGET_PLATFORM/_test*/}.plist"
#$sed -e '/CFBundleIdentifier/{n;s#>.*<#>'${ACT_PACKAGE_NAME}'<#g}' -i "${infoplist}"
## app name
# $sed -e '/CFBundleDisplayName/{n;s#>.*<#>'${ACT_APP_NAME}'<#g}' -i "${infoplist}"
buildVersion=$($sed -n '/CFBundleVersion/{n;s#.*>\(.*\)<.*#\1#p}' "${infoplist}" | cut -d '.' -f4)
buildVersion=${buildVersion-'0'}
buildVersion=$((buildVersion+1))
$sed -e '/CFBundleVersion/{n;s#>.*<#>'"${GEN_VERSION}.${buildVersion}"'<#g}' -i "${infoplist}"
$sed -e '/CFBundleShortVersionString/{n;s#>.*<#>'${GEN_VERSION}'<#g}' -i "${infoplist}"
${svn} ci --username "${svnusername}" --password "${svnpassword}" --no-auth-cache "${infoplist}" -m "auto update CFBundleVersion etc. in ${infoplist}"
# cat "${infoplist}"

# # > 更新 `src.cfg/config.${ACT_TARGET_PLATFORM}.lua` 中的 VERSION, SVN_VERSION 等动态参数
echo "update src.cfg/config.${ACT_TARGET_PLATFORM}.lua ..."
$update_config_lua "../../../src.cfg/config.${ACT_TARGET_PLATFORM}.lua" "ACT_TARGET_PLATFORM=${ACT_TARGET_PLATFORM}"
${svn} ci --username "${svnusername}" --password "${svnpassword}" --no-auth-cache "../../../src.cfg" -m "auto update src.cfg/config.${ACT_TARGET_PLATFORM}.lua"

# # > 解锁钥匙串
echo "unlock-keychain ..."
security unlock-keychain -pcvcv  "/Users/"$(whoami)"/Library/Keychains/login.keychain"

# # > 编译 c++ 代码, 生成 `ActGame_{platform}.app`
${buildtool} -target "${target}" -verbose -jobs 4 ${archs} ${sdk} -configuration "${ACT_BUILD_CONFIGURATION}" CONFIGURATION_BUILD_DIR=build/ #DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM} CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" PROVISIONING_PROFILE=${PROVISIONING_PROFILE}

# # > 拷贝 `res`, `src` 到 `ActGame_{platform}.app/` 目录
# rm -rf build/${target}.app/main.* build/${target}.app/res ${target}.app/src
#echo "copy src ..."
#cp    ../../../main.* "build/${target}.app/"
#cp -r "../../../src" "build/${target}.app/"
#echo "copy res ..."
#cp -r "../res_${branch}/res" "build/${target}.app/"

# # > 拷贝 `src.cfg/config.{platform}.lua` 到 `ActGame_{platform}.app/src/config.lua`
#echo "copy src.cfg/config.${ACT_TARGET_PLATFORM}.lua ..."
#cp -r "../../../src.cfg/config.${ACT_TARGET_PLATFORM}.lua" "build/${target}.app/src/config.lua"

# # > 加密 `ActGame_{platform}.app/(src|res)`
#$xxtea "build/${target}.app/src"
#$xxtea "build/${target}.app/res"

# # > 拷贝 `ios/Info.{platform}.plist` 到 `ActGame_{platform}.app/Info.plist`
# echo "cp ios/Info.${ACT_TARGET_PLATFORM}.plist ..."
# cp -f "ios/Info.${ACT_TARGET_PLATFORM}.plist" "build/${target}.app/"

rm -f build/*.ipa

# # > 打包, 签名
echo "package ..."
xcrun --sdk iphoneos PackageApplication -v "build/${target}.app" -o "$(pwd)/build/${target}.ipa" --sign "${CODE_SIGN_IDENTITY}"

# # > 重命名 `{target}.ipa` 为 `mfsn-{platform}-{version}-{build_number}.ipa`
ipaname="mfsn-${ACT_TARGET_PLATFORM}-${GEN_VERSION}.${buildVersion}-${svnhead}-${BUILD_NUMBER}.ipa"
mv "build/${target}.ipa" "build/${ipaname}"

# # > 上传内网 ftp 备份
pushd "build"
$upload "${ipaname}"
popd

# # > 记录 `VERSION`, `SVN_VERSION` 到 `build_history/{platform}.verson` 和 `build_history/{platform}.version_history` 中 
mkdir -p "../../../build_history"
echo "${ACT_TARGET_PLATFORM} ${svnhead}=${GEN_VERSION}"
if [[ ${ACT_UPDAE_ONLENI_VERSION} == 'true' ]]; then
	echo "${svnhead}=${GEN_VERSION}" > "../../../build_history/${ACT_TARGET_PLATFORM}.update_history"
else
	echo "${svnhead}=${GEN_VERSION}" >> "../../../build_history/${ACT_TARGET_PLATFORM}.update_history"
fi
pushd "../../../build_history/"
$upload "${ACT_TARGET_PLATFORM}.version.lua" "version.lua"
## 上传阿里云
if [[ ${AUTO_UPLOAD_OSS} == "true" ]]; then
	echo "upload ${ACT_TARGET_PLATFORM}.version.lua to aliyun oss ..."
	${aloss} Put "${ACT_TARGET_PLATFORM}.version.lua" "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	${aloss} Cat "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	echo "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
	echo "http://line1.patch.madoka.biligame.net/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/version.lua"
fi
cat "${ACT_TARGET_PLATFORM}.version.lua"
popd

# # > 更新内网下载页面
downloadplist="${ACT_TARGET_PLATFORM}-${BUILD_NUMBER}.plist"
cp "download.plist" ${downloadplist}
pkgurl="${ACT_UPLOAD_FTP/*=/}/${ACT_TARGET_PLATFORM}/${ipaname}"
$sed -e "s#http://act.ipa#"${pkgurl}"#g" -i ${downloadplist}

mkdir -p qr
qrurl="itms-services://?action=download-manifest&amp;url=https://raw.githubusercontent.com/cn00/https/master/${downloadplist}"
qrencode "${qrurl}" -t png -o "qr/${ipaname}.png"
scp "qr/${ipaname}.png" "${ACT_UPLOAD_FTP/=*}/${ACT_TARGET_PLATFORM}/qr/"
if [[ ! -f "../html/dl-${ACT_TARGET_PLATFORM}.html" ]]; then
	cp "../html/dl-template.html" "../html/dl-${ACT_TARGET_PLATFORM}.html"
	$sed '/<!--ipadownloadpage-->/a\    <a href="'${ACT_UPLOAD_FTP/*=}$'/dl-'${ACT_TARGET_PLATFORM}$'.html"><h2>'"${branch}"':'${ACT_TARGET_PLATFORM}$'</h2></a><br/>' -i "../html/index.html"
	${svn} ci "../html/index.html" --username "${svnusername}" --password "${svnpassword}" --no-auth-cache -m "auto update html/index.html"
	scp "../html/index.html" "${ACT_UPLOAD_FTP/:*}:" ## home page
fi
$sed '/<\!-- ipabegin -->/a\    <a href="'"${qrurl}"$'" class="cye-lm-tag"><img src="'${ACT_TARGET_PLATFORM}$'/qr/'${ipaname}$'.png" title="魔法少女小圆"></a><br/><a href="'${pkgurl}$'">'${ipaname}$'</a><br/>'"$(date)"$'<br/><br/>' -i "../html/dl-${ACT_TARGET_PLATFORM}.html"
scp "../html/dl-${ACT_TARGET_PLATFORM}.html" "${ACT_UPLOAD_FTP/=*}"

mv "${downloadplist}" "../../../../https/"
pushd "../../../../https"
git add .
git ci -m "add ${downloadplist}"
# git push
popd

## 上传阿里云
if [[ ${AUTO_UPLOAD_OSS} == "true" ]]; then
	echo "upload ${ipaname} to aliyun oss ..."
	${aloss} Put "build/${ipaname}" "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${ipaname}"
	echo "${ossmfsn}/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${apkname}"
	echo "http://line1.patch.madoka.biligame.net/${ACT_OSS_ROOT}/${ACT_TARGET_PLATFORM}/${ipaname}"
fi

popd ## frameworks/runtime-src/proj.ios_mac 
