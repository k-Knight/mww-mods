cmake_minimum_required(VERSION 3.15)
set(CMAKE_TRY_COMPILE_TARGET_TYPE "STATIC_LIBRARY")
project(GamepadSupportProject LANGUAGES CXX)

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

add_library(sdl_gamepad_listener SHARED gamepad_state.hpp gamepad_listener.cpp)

target_include_directories(sdl_gamepad_listener PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../sdl/include")
target_link_directories(sdl_gamepad_listener PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../sdl/lib/x86")
target_link_libraries(sdl_gamepad_listener PRIVATE SDL2)

set_target_properties(sdl_gamepad_listener PROPERTIES
    MSVC_RUNTIME_LIBRARY $<IF:$<CONFIG:Release>,MultiThreaded,MultiThreadedDebug>
)

target_link_options(sdl_gamepad_listener PRIVATE
    -Wl,/ignore:4099
    -Wl,/SUBSYSTEM:$<IF:$<CONFIG:Release>,WINDOWS,CONSOLE>
)

add_executable(gamepad_viewer tester.cpp)

set_target_properties(gamepad_viewer PROPERTIES
    MSVC_RUNTIME_LIBRARY $<IF:$<CONFIG:Release>,MultiThreaded,MultiThreadedDebug>
)

target_link_options(gamepad_viewer PRIVATE
    -Wl,/ignore:4099
    -Wl,/SUBSYSTEM:WINDOWS
)
