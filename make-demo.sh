#!/bin/bash
set -e

RN_VER=0.73.2
RNFB_VER=18.7.3
FB_IOS_VER=10.19.0
FB_ANDROID_VER=32.7.0
FB_GRADLE_SERVICES_VER=4.4.0
FB_GRADLE_PERF_VER=1.4.2
FB_GRADLE_CRASH_VER=2.9.9
FB_GRADLE_APP_DIST_VER=4.0.1

#######################################################################################################
#######################################################################################################
# This whole section is test setup, and environment verification, it does not represent integration yet
# Test: We need to verify our environment first, so we fail fast for easily detectable things
if [ "$(uname)" == "Darwin" ]; then
  # If the keychain is unlocked then this fails in the middle, let's check that now and fail fast
  if ! security show-keychain-info login.keychain > /dev/null 2>&1; then
    echo "Login keychain is not unlocked, codesigning will fail so macCatalyst build wll fail."
    echo "run 'security unlock-keychain login.keychain' to unlock the login keychain then re-run"
    exit 1
  fi

  # We do not want to run under Rosetta 2, brew doesn't work and compiles might not work after
  arch_name="$(uname -m)"
  if [ "${arch_name}" = "x86_64" ]; then
    if [ "$(sysctl -in sysctl.proc_translated)" = "1" ]; then
      echo "Running on Rosetta 2"
      echo "This is not supported. Run \`env /usr/bin/arch -arm64 /bin/bash --login\` then try again"
      exit 1
    else
      echo "Running on native Intel"
    fi
  elif [ "${arch_name}" = "arm64" ]; then
    echo "Running on ARM"
  else
    echo "Unknown architecture: ${arch_name}"
  fi

  # We need a development team or macCatalyst build will fail
  if [ "$XCODE_DEVELOPMENT_TEAM" == "" ]; then
    printf "\n\n\n\n\n**********************************\n\n\n\n"
    printf "You must set XCODE_DEVELOPMENT_TEAM environment variable to your team id to test macCatalyst"
    printf "Try running it like: XCODE_DEVELOPMENT_TEAM=2W4T2B656C ./make-demo.sh (but with your id)"
    printf "Skipping macCatalyst test"
    printf "\n\n\n\n\n**********************************\n\n\n\n"
  fi
fi

# Test: Previous compiles may confound future compiles, erase...
\rm -fr "$HOME/Library/Developer/Xcode/DerivedData/paidsurveys*"

# Test: Basic template create, rnfb install, link
\rm -fr paidsurveys

echo "Testing react-native ${RN_VER} + react-native-firebase ${RNFB_VER} + firebase-ios-sdk ${FB_IOS_VER} + firebase-android-sdk ${FB_ANDROID_VER}"

if ! which yarn > /dev/null 2>&1; then
  echo "This script uses yarn, please install yarn (for example \`npm i yarn -g\` and re-try"
  exit 1
fi
#######################################################################################################
#######################################################################################################




# Let's test react-native-firebase integration! Here is how you do it.


# Initialize a fresh project.
# We say "skip-install" because we control our ruby version and cocoapods (part of install) does not like it
npm_config_yes=true npx react-native@${RN_VER} init paidsurveys --skip-install --version=${RN_VER}
cd paidsurveys

# New versions of react-native include annoying Ruby stuff that forces use of old rubies. Obliterate.
if [ -f Gemfile ]; then
  rm -f Gemfile* .ruby*
fi

# Now run our initial dependency install
yarn
npm_config_yes=true npx pod-install

# At this point we have a clean react-native project. Absolutely stock from the upstream template.

# Required: This is the most basic part of the integration - include google services plugin and call to firebase init on iOS
echo "Adding react-native-firebase core app package"
yarn add "@react-native-firebase/app@${RNFB_VER}"
echo "Adding basic iOS integration - AppDelegate import and config call"
sed -i -e $'s/AppDelegate.h"/AppDelegate.h"\\\n#import <Firebase.h>/' ios/paidsurveys/AppDelegate.m*
rm -f ios/paidsurveys/AppDelegate.m*-e
sed -i -e $'s/self.moduleName/[FIRApp configure];\\\n  self.moduleName/' ios/paidsurveys/AppDelegate.m*
rm -f ios/paidsurveys/AppDelegate.m*-e
echo "Adding basic java integration - gradle plugin dependency and call"
sed -i -e $"s/dependencies {/dependencies {\n        classpath \"com.google.gms:google-services:${FB_GRADLE_SERVICES_VER}\"/" android/build.gradle
rm -f android/build.gradle??
sed -i -e $'s/apply plugin: "com.android.application"/apply plugin: "com.android.application"\\\napply plugin: "com.google.gms.google-services"/' android/app/build.gradle
rm -f android/app/build.gradle??

#############################################################################################################
# Required: Static Frameworks linkage set up in cocoapods, and various related workarounds for compatibility.
#############################################################################################################

# You have two options here:
# - One is to dynamically disable flipper and turn on static frameworks with environment variables at build time
# - Two is to permanently disable flipper and turn on static frameworks with Podfile edits

# The default way a new react-native app is built from template uses method One, environment variables.
# I worry that some developer somewhere will not have these environment variables set correctly though,
# causing an unexpected build failure.

# So we choose option Two, where we permanently disable Flipper and enable static frameworks in the Podfile.

# Required: turn on static frameworks with static linkage, and tell react-native-firebase that is how we are linking
sed -i -e $'s/config = use_native_modules!/config = use_native_modules!\\\n  use_frameworks! :linkage => :static\\\n  $RNFirebaseAsStaticFramework = true/' ios/Podfile

# Required Workaround: Static frameworks does not work with flipper - toggle it off (follow/vote: https://github.com/facebook/flipper/issues/3861)
sed -i -e $'s/:flipper_configuration/# :flipper_configuration/' ios/Podfile
rm -f ios/Podfile.??

# We control our pod installation manually, and do not want react-native CLI doing it
# Otherwise, sometimes we see compile errors disguised as pod installation errors
# This was removed between 0.73.0 and 0.73.1
#sed -i -e $'s/automaticPodsInstallation/\/\/ automaticPodsInstallation/' react-native.config.js
#rm -f react-native.config.js-e
#############################################################################################################


# Required: copy your Firebase config files in - you must supply them, downloaded from firebase web console
echo "For this demo to work, you must create an \`paidsurveys\` project in your firebase console,"
echo "then download the android json and iOS plist app definition files to the root directory"
echo "of this repository"

echo "Copying in Firebase android json and iOS plist app definition files downloaded from console"

if [ "$(uname)" == "Darwin" ]; then
  if [ -f "../GoogleService-Info.plist" ]; then
    cp ../GoogleService-Info.plist ios/paidsurveys/
  else
    echo "Unable to locate the file 'GoogleServices-Info.plist', did you create the firebase project and download the iOS file?"
    exit 1
  fi
fi
if [ -f "../google-services.json" ]; then
  cp ../google-services.json android/app/
else
  echo "Unable to locate the file 'google-services.json', did you create the firebase project and download the android file?"
  exit 1
fi


##################################################################################################
# This section is only required for the script to work fully automatic.
# In your project you will use Xcode user interface to add your GoogleService-Info.plist file
##################################################################################################
# Set up python virtual environment so we can do some local mods to Xcode project with mod-pbxproj
# FIXME need to verify that python3 exists (recommend brew) and has venv module installed
if [ "$(uname)" == "Darwin" ]; then
  echo "Setting up python virtual environment + mod-pbxproj for Xcode project edits"
  python3 -m venv virtualenv
  # shellcheck disable=SC1091
  source virtualenv/bin/activate
  pip install pbxproj

  # set PRODUCT_BUNDLE_IDENTIFIER to com.paidsurveys
  sed -i -e $'s/org.reactjs.native.example/com/' ios/paidsurveys.xcodeproj/project.pbxproj
  rm -f ios/paidsurveys.xcodeproj/project.pbxproj-e

  # Add our Google Services file to the Xcode project
  pbxproj file ios/paidsurveys.xcodeproj paidsurveys/GoogleService-Info.plist --target paidsurveys

  # Toggle on iPad: add build flag: TARGETED_DEVICE_FAMILY = "1,2"
  pbxproj flag ios/paidsurveys.xcodeproj --target paidsurveys TARGETED_DEVICE_FAMILY "1,2"
fi
##################################################################################################


# From this point on we are adding optional modules. We test them all so we add them all. You only need to add what you need.
# First set up all the modules that need no further config for the demo
echo "Adding packages: Analytics, App Check, Auth, Database, Dynamic Links, Firestore, Functions, In App Messaging, Installations, Messaging, ML, Remote Config, Storage"
yarn add \
  @react-native-firebase/analytics@${RNFB_VER} \
  @react-native-firebase/app-check@${RNFB_VER} \
  @react-native-firebase/auth@${RNFB_VER} \
  @react-native-firebase/messaging@${RNFB_VER} \
  @react-native-firebase/remote-config@${RNFB_VER} \

## Optional: Crashlytics - repo, classpath, plugin, dependency, import, init
#echo "Setting up Crashlytics - package, gradle plugin"
#yarn add "@react-native-firebase/crashlytics@${RNFB_VER}"
#sed -i -e $"s/dependencies {/dependencies {\n        classpath \"com.google.firebase:firebase-crashlytics-gradle:${FB_GRADLE_CRASH_VER}\"/" android/build.gradle
#rm -f android/build.gradle??
#sed -i -e $'s/"com.google.gms.google-services"/"com.google.gms.google-services"\\\napply plugin: "com.google.firebase.crashlytics"/' android/app/build.gradle
#rm -f android/app/build.gradle??
#sed -i -e $'s/proguardFiles getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro"/proguardFiles getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro"\\\n            firebaseCrashlytics {\\\n                nativeSymbolUploadEnabled true\\\n                unstrippedNativeLibsDir "build\/intermediates\/merged_native_libs\/release\/out\/lib"\\\n            }/' android/app/build.gradle
#rm -f android/app/build.gradle??

# My custom modules
yarn add inbrain-surveys react-native-plugin-pollfish @notifee/react-native
yarn add @react-native-clipboard/clipboard @react-native-google-signin/google-signin @react-navigation/native @react-navigation/native-stack
yarn add react-native-config react-native-device-info react-native-in-app-review react-native-linear-gradient react-native-localize react-native-safe-area-context react-native-screens react-native-svg react-native-webview validator


## Optional: Performance - classpath, plugin, dependency, import, init
#echo "Setting up Performance - package, gradle plugin"
#yarn add "@react-native-firebase/perf@${RNFB_VER}"
#rm -f android/app/build.gradle??
#sed -i -e $"s/dependencies {/dependencies {\n        classpath \"com.google.firebase:perf-plugin:${FB_GRADLE_PERF_VER}\"/" android/build.gradle
#rm -f android/build.gradle??
#sed -i -e $'s/"com.google.gms.google-services"/"com.google.gms.google-services"\\\napply plugin: "com.google.firebase.firebase-perf"/' android/app/build.gradle
#rm -f android/app/build.gradle??
#
## Optional: App Distribution - classpath, plugin, dependency, import, init
#echo "Setting up App Distribution - package, gradle plugin"
#yarn add "@react-native-firebase/app-distribution@${RNFB_VER}"
#sed -i -e $"s/dependencies {/dependencies {\n        classpath \"com.google.firebase:firebase-appdistribution-gradle:${FB_GRADLE_APP_DIST_VER}\"/" android/build.gradle
#rm -f android/build.gradle??

# Required for Firestore - android build tweak - or gradle runs out of memory during the build
echo "Increasing memory available to gradle for android java build"
echo "org.gradle.jvmargs=-Xmx3072m -Dfile.encoding=UTF-8" >> android/gradle.properties

# I'm not going to demonstrate messaging and notifications. Everyone gets it wrong because it's hard.
# You've got to read the docs and test *EVERYTHING* one feature at a time.
# But you have to do a *lot* of work in the AndroidManifest.xml, and make sure your MainActivity *is* the launch intent receiver
# I include it for compile testing only.

# Optional: do you want to configure firebase behavior via firebase.json?
echo "Creating default firebase.json (with settings that allow iOS crashlytics to report crashes even in debug mode)"
printf "{\n  \"react-native\": {\n    \"crashlytics_disable_auto_disabler\": true,\n    \"crashlytics_debug_enabled\": true\n  }\n}" > firebase.json

# Optional: allow explicit SDK version control by specifying our iOS Pods and Android Firebase Bill of Materials
echo "Adding upstream SDK overrides for precise version control"
echo "project.ext{set('react-native',[versions:[firebase:[bom:'${FB_ANDROID_VER}'],],])}" >> android/build.gradle
sed -i -e $"s/  target 'paidsurveysTests' do/  \$FirebaseSDKVersion = '${FB_IOS_VER}'\n  target 'paidsurveysTests' do/" ios/Podfile
rm -f ios/Podfile??

# Optional: build performance - use pre-built version of Firestore - https://github.com/invertase/firestore-ios-sdk-frameworks
# If you are using firestore and database you *may* end up with duplicate symbol build errors referencing "leveldb", the FirebaseFirestoreExcludeLeveldb boolean fixes that.
#sed -i -e $'s/  target \'paidsurveysTests\' do/  $FirebaseFirestoreExcludeLeveldb = true\\\n  pod \'FirebaseFirestore\', :git => \'https:\\/\\/github.com\\/invertase\\/firestore-ios-sdk-frameworks.git\', :tag => $FirebaseSDKVersion\\\n  target \'paidsurveysTests\' do/' ios/Podfile
#rm -f ios/Podfile??

# Optional: Apple M1 workaround - builds may have a problem with architectures on Apple Silicon and Intel, some exclusions may help
sed -i -e $'s/post_install do |installer|/post_install do |installer|\\\n    installer.aggregate_targets.each do |aggregate_target|\\\n      aggregate_target.user_project.native_targets.each do |target|\\\n        target.build_configurations.each do |config|\\\n          config.build_settings[\'ONLY_ACTIVE_ARCH\'] = \'YES\'\\\n          config.build_settings[\'EXCLUDED_ARCHS\'] = \'i386\'\\\n        end\\\n      end\\\n      aggregate_target.user_project.save\\\n    end\\\n/' ios/Podfile
rm -f ios/Podfile.??

# Optional: build performance optimization to use ccache - asks xcodebuild to use clang and clang++ without the fully-qualified path
# That means that you can then make a symlink in your path with clang or clang++ and have it use a different binary
# In that way you can install ccache or buildcache and get much faster compiles...
sed -i -e $'s/post_install do |installer|/post_install do |installer|\\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["CC"] = "clang"\\\n        config.build_settings["LD"] = "clang"\\\n        config.build_settings["CXX"] = "clang++"\\\n        config.build_settings["LDPLUSPLUS"] = "clang++"\\\n      end\\\n    end\\\n/' ios/Podfile
rm -f ios/Podfile??

# Optional: Cleaner build logs - libevent pulled in by react core / flipper items are ridiculously noisy otherwise
sed -i -e $'s/post_install do |installer|/post_install do |installer|\\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["GCC_WARN_INHIBIT_ALL_WARNINGS"] = "YES"\\\n      end\\\n    end\\\n/' ios/Podfile
rm -f ios/Podfile??

# Test: Copy in our demonstrator App.tsx
echo "Copying demonstrator App.tsx"
rm ./App.tsx && cp ../App.tsx ./App.tsx

# Test: You have to re-run patch-package after yarn since it is not integrated into postinstall, so run it again
echo "Running any patches necessary to compile successfully"
cp -rv ../patches .
npm_config_yes=true npx patch-package

# Start up the packager - for some reason not starting automatically at the moment...
yarn start --no-interactive &

# Test: Run the thing for iOS
if [ "$(uname)" == "Darwin" ]; then

  echo "Installing pods and running iOS app in debug mode"
  npm_config_yes=true npx pod-install

  # Check iOS debug mode compile
  npx react-native run-ios --mode Debug

  # Check iOS release mode compile
  echo "Installing pods and running iOS app in release mode"
  npx react-native run-ios --mode Release

  # Optional: Check catalyst build
  if ! [ "$XCODE_DEVELOPMENT_TEAM" == "" ]; then

    #################################################################################################
    # This section is so the script may work fully automatic.
    # If you are targeting macCatalyst, you will use the Xcode UI to add your development team.
    # add file paidsurveys/paidsurveys.entitlements, with reference to paidsurveys target, but no build phase
    echo "Adding macCatalyst entitlements file / build flags to Xcode project"
    cp ../paidsurveys.entitlements ios/paidsurveys/
    pbxproj file ios/paidsurveys.xcodeproj paidsurveys/paidsurveys.entitlements --target paidsurveys -C
    # add build flag: CODE_SIGN_ENTITLEMENTS = paidsurveys/paidsurveys.entitlements
    pbxproj flag ios/paidsurveys.xcodeproj --target paidsurveys CODE_SIGN_ENTITLEMENTS paidsurveys/paidsurveys.entitlements
    # add build flag: SUPPORTS_MACCATALYST = YES
    pbxproj flag ios/paidsurveys.xcodeproj --target paidsurveys SUPPORTS_MACCATALYST YES
    # add build flag 				DEVELOPMENT_TEAM = 2W4T2B656C;
    pbxproj flag ios/paidsurveys.xcodeproj --target paidsurveys DEVELOPMENT_TEAM "$XCODE_DEVELOPMENT_TEAM"
    #################################################################################################

    # Required for macCatalyst: Podfile workarounds for signing and library paths are built-in 0.70+ with a specific flag:
    sed -i -e $'s/mac_catalyst_enabled => false/mac_catalyst_enabled => true/' ios/Podfile

    echo "Installing pods and running iOS app in macCatalyst mode"
    npm_config_yes=true npx pod-install

    # Now run it with our mac device name as device target, that triggers catalyst build
    # Need to check if the development team id is valid? error 70 indicates team not added as account / cert not present / xcode does not have access to keychain?

    # For some reason, the device id returned if you use the computer name is wrong.
    # It is also wrong from ios-deploy or xcrun xctrace list devices
    # The only way I have found to get the right ID is to provide the wrong one then parse out the available one
    CATALYST_DESTINATION=$(xcodebuild -workspace ios/paidsurveys.xcworkspace -configuration Debug -scheme paidsurveys -destination id=7153382A-C92B-5798-BEA3-D82D195F25F8 2>&1|grep macOS|grep Catalyst|head -1 |cut -d':' -f5 |cut -d' ' -f1)

    # FIXME This requires a CLI patch to the iOS platform to accept a UDID it cannot probe, and to set type to catalyst
    npx react-native run-ios --udid "$CATALYST_DESTINATION" --mode Debug
  fi

  # Optional: workaround for poorly setup Android SDK environments on macs
  USER=$(whoami)
  echo "sdk.dir=/Users/$USER/Library/Android/sdk" > android/local.properties
fi

# Test: make sure proguard works
echo "Configuring Android release build for ABI splits and code shrinking"
sed -i -e $'s/def enableProguardInReleaseBuilds = false/def enableProguardInReleaseBuilds = true/' android/app/build.gradle
rm -f android/app/build.gradle??

# Test: If we are on WSL the user needs to now run it from the Windows side
# Getting it to run from WSL is a real mess (it is possible, but not recommended)
# So we will stop now that we've done all the installation and file editing
if [ "$(uname -a | grep Linux | grep -c microsoft)" == "1" ]; then
  echo "Detected Windows Subsystem for Linux. Stopping now."

  # Clear out the unix-y node_modules
  \rm -fr node_modules
  echo "To run the app use Windows Powershell in the paidsurveys directory with these commands:"
  echo "npm i"
  echo "npx react-native run-android --mode debug"
  exit
fi

# Test: uninstall it (just in case, otherwise ABI-split-generated version codes will prevent debug from installing)
pushd android
./gradlew uninstallRelease
popd

# Test: Run it for Android (assumes you have an android emulator running)
echo "Running android app in release mode"
npx react-native run-android --mode release

# Test: Let it start up, then uninstall it (otherwise ABI-split-generated version codes will prevent debug from installing)
sleep 30
pushd android
./gradlew uninstallRelease
popd

# Workaround flipper crash problem until Android Marshmallow (release 6+)
# see https://github.com/facebook/flipper/issues/3572
sed -i -e 's/^import android.app.Application/import android.app.Application\nimport android.os.Build/' android/app/src/main/java/com/paidsurveys/MainApplication.kt
sed -i -e 's/^    ReactNativeFlipper.initializeFlipper(this, reactNativeHost.reactInstanceManager)/    if (Build.VERSION.SDK_INT > Build.VERSION_CODES.LOLLIPOP_MR1) {\n      ReactNativeFlipper.initializeFlipper(this, reactNativeHost.reactInstanceManager)\n    }/' android/app/src/main/java/com/paidsurveys/MainApplication.kt
rm -f android/app/src/main/java/com/paidsurveys/MainApplication.kt??

# Test: may or may not be commented out, depending on if have an emulator available
# I run it manually in testing when I have one, comment if you like
echo "Running android app in debug mode"
npx react-native run-android --mode debug
