work_path=$(pwd)
engine_path=
platform=
gn_params=""
optimize="--unoptimized"
ninja_params=""
runtime_mode=


echo "setting environment variable and other params..."

while getopts ":r:p:m:eo" opt
do
    case $opt in
        r)
        engine_path=$OPTARG # set engine_path, depot_tools and flutter engine folder will be put into this path
        ;;
        p)
        gn_params="$gn_params --$OPTARG" # set the target platform android/ios
        ;;
        m)
        runtime_mode=$OPTARG
        gn_params="$gn_params --runtime-mode=$runtime_mode" # set runtime mode release/debug
        ;;
        e)
        gn_params="$gn_params --bitcode" # enable-bitcode switch
        ;;
        o)
        optimize="" # optimize code switch
        ;;
        ?)
        echo "unknown param"
        exit 1;;
    esac
done

if [ "$runtime_mode" == "release" ] && [ "$optimize" == "--unoptimized" ];
then
  output_path="host_release_unopt"
  ninja_params=" -C out/host_release_unopt flutter/third_party/txt:txt_lib"
elif [ "$runtime_mode" == "release" ] && [ "$optimize" == "" ];
then
  output_path="host_release"
  ninja_params="-C out/host_release flutter/third_party/txt:txt_lib"
elif [ "$runtime_mode" == "debug" ] && [ "$optimize" == "--unoptimized" ];
then
  output_path="host_debug_unopt"
  ninja_params=" -C out/host_debug_unopt flutter/third_party/txt:txt_lib"
elif [ "$runtime_mode" == "debug" ] && [ "$optimize" == "" ];
then
  output_path="host_debug"
  ninja_params=" -C out/host_debug flutter/third_party/txt:txt_lib"
elif [ "$runtime_mode" == "profile" ];
then
  echo "not support profile build yet"
  exit 1
fi

gn_params="$gn_params $optimize"

#set environment variable
function isexist()
{
    source_str=$1
    test_str=$2
    
    strings=$(echo $source_str | sed 's/:/ /g')
    for str in $strings
    do  
        if [ $test_str = $str ]; then
            return 0
        fi  
    done
    return 1
}

if [ ! $FLUTTER_ROOT_PATH ];then
  echo "export FLUTTER_ROOT_PATH=$engine_path/engine/src" >> ~/.bash_profile
else
  echo "This environment variable has been set, skip"
fi

if isexist $PATH $engine_path/depot_tools; then 
  echo "This environment variable has been set, skip"
else 
  echo "export PATH=$engine_path/depot_tools:\$PATH" >> ~/.bash_profile
fi
source ~/.bash_profile

echo "\nGetting Depot Tools..." 
if [ ! -n "$engine_path" ]; then   
  echo "Flutter engine path is not exist, please set the path by using \"-r\" param to set an engine path."  
  exit 1
fi
cd $engine_path	
if [ -d 'depot_tools' ] && [ -d "depot_tools/.git" ];
then
  echo "depot_tools already installed, skip"
else
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  gclient
fi

echo "\nGetting flutter engine..."

if [ -d 'engine' ];
then
  echo "engine folder already exist, skip"
else
  mkdir engine
fi
cd engine
#git@github.com:guanghuispark/engine.git is a temp repo, replace it later
echo "solutions = [
  {
    \"managed\": False,
    \"name\": \"src/flutter\",
    \"url\": \"git@github.com:guanghuispark/engine.git\", 
    \"custom_deps\": {},
    \"deps_file\": \"DEPS\",
    \"safesync_url\": \"\",
  },
]" > .gclient

gclient sync

cd src/flutter
git checkout flutter-1.17-candidate.5
gclient sync -D

echo "\nSCompiling engine..."
#apply patch to Build.gn
cd third_party/txt
cp -f $work_path/patches/BUILD.gn.patch BUILD.gn.patch
patch < BUILD.gn.patch -N

cd $engine_path/engine/src/build/mac
cp -f $work_path/patches/find_sdk.patch find_sdk.patch
patch < find_sdk.patch -N
cd ../..
./flutter/tools/gn $gn_params

echo "icu_use_data_file=false" >> out/$output_path/args.gn
ninja $ninja_params

echo "\nStarting build engine..."
cd $work_path
cd ..
if [ "$runtime_mode" == "release" ];
then
  mono bee.exe mac_release
  if [ -d '../com.unity.uiwidgets/Runtime/Plugins/osx' ];
  then
    echo "engine folder already exist, skip"
  else
    mkdir ../com.unity.uiwidgets/Runtime/Plugins/osx
  fi
  rm -rf ../com.unity.uiwidgets/Runtime/Plugins/osx/*
  cp -r build_release/. ../com.unity.uiwidgets/Runtime/Plugins/osx
elif [ "$runtime_mode" == "debug" ];
then
  mono bee.exe mac_debug
  if [ -d '../com.unity.uiwidgets/Runtime/Plugins/osx' ];
  then
    echo "engine folder already exist, skip create folder"
  else
    mkdir ../com.unity.uiwidgets/Runtime/Plugins/osx
  fi
  rm -rf ../com.unity.uiwidgets/Runtime/Plugins/osx/*
  cp -r build_debug/. ../com.unity.uiwidgets/Runtime/Plugins/osx
fi
