# fm2 - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(fm2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(FM2_SOURCES
    src/main.cpp
    src/hooks.cpp
)

if(WIN32)
    add_executable(fm2 WIN32 ${FM2_SOURCES})
else()
    add_executable(fm2 ${FM2_SOURCES})
endif()

rexglue_setup_target(fm2 GPU_PLUGINS xenos)
