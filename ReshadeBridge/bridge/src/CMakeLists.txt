cmake_minimum_required(VERSION 3.15)
set(CMAKE_TRY_COMPILE_TARGET_TYPE "STATIC_LIBRARY")
project(ReshadeBridgeProject LANGUAGES CXX)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/../bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/../bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/../bin")
set(BUILD_SHARED_LIBS TRUE)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    enable_language(RC)
endif()

add_compile_options(
    -target i686-pc-windows-msvc
    -m32
    -static
    -O3
    -DUNICODE
    -D_UNICODE
    -D_CRT_SECURE_NO_WARNINGS
    -DRESHADE_API_VERSION=18
    $<$<CONFIG:Debug>:-fms-runtime-lib=static_dbg>
    $<$<CONFIG:Release>:-fms-runtime-lib=static>
)

add_link_options(
    -m32
    -static
    -O3
    -municode
    $<$<CONFIG:Debug>:-fms-runtime-lib=static_dbg>
    $<$<CONFIG:Release>:-fms-runtime-lib=static>
)

add_library(reshade_bridge SHARED main.cpp)

set_target_properties(reshade_bridge PROPERTIES 
    SUFFIX ".addon32"
)

target_include_directories(reshade_bridge PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")

set_target_properties(reshade_bridge PROPERTIES
    MSVC_RUNTIME_LIBRARY $<IF:$<CONFIG:Release>,MultiThreaded,MultiThreadedDebug>
)

target_link_options(reshade_bridge PRIVATE
    -Wl,/ignore:4099
    -Wl,/SUBSYSTEM:$<IF:$<CONFIG:Release>,WINDOWS,CONSOLE>
)
