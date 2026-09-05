# FM2 Recomp

cmake_minimum_required(VERSION 3.25)
project(fm2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(cmake/rexglue.cmake)

# Sources
set(FM2_SOURCES
    src/compat_math.cpp
    src/fm2_app.cpp
    src/main.cpp
    src/hooks.cpp
)

if(WIN32)
    add_executable(fm2 WIN32 ${FM2_SOURCES})
else()
    add_executable(fm2 ${FM2_SOURCES})
endif()

rexglue_setup_target(fm2 GPU_PLUGINS xenos)

# Keep the runtime configuration beside the executable for local builds and
# release packaging. Users can still override any value on the command line.
add_custom_command(TARGET fm2 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/fm2_runtime.toml"
        "$<TARGET_FILE_DIR:fm2>/fm2.toml"
    VERBATIM
)
