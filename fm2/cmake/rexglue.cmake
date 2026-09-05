# ReXGlue integration kept in source control so a fresh clone can configure
# before game-specific generated sources exist.

set(REXSDK_DIR "" CACHE PATH "Optional path to a ReXGlue SDK source tree")
set(REXSDK_PACKAGE_DIR "" CACHE PATH "Optional path to a packaged ReXGlue SDK")

if(REXSDK_PACKAGE_DIR)
    find_package(rexglue CONFIG REQUIRED
        PATHS "${REXSDK_PACKAGE_DIR}"
        NO_DEFAULT_PATH
    )
    message(STATUS "Using packaged ReXGlue SDK: ${REXSDK_PACKAGE_DIR}")
elseif(REXSDK_DIR)
    add_subdirectory("${REXSDK_DIR}" rexglue-sdk)
    message(STATUS "Using ReXGlue SDK from source tree: ${REXSDK_DIR}")
else()
    # FM2's full function map relies on continuation-alias handling which is
    # newer than its original SDK snapshot. Pin the public compatible fork so
    # clean clones all build and generate against the same implementation.
    include(FetchContent)
    FetchContent_Declare(fm2_rexglue_sdk
        GIT_REPOSITORY https://github.com/Alexbeav/rexglue-sdk.git
        GIT_TAG f16992c92e610c2d71773994436b442d9946f4e1
        GIT_SHALLOW FALSE
        GIT_SUBMODULES_RECURSE TRUE
    )
    FetchContent_MakeAvailable(fm2_rexglue_sdk)
    message(STATUS "Using pinned FM2-compatible ReXGlue SDK revision f16992c")
endif()

set(REXGLUE_HOST_TARGET fm2)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/generated/default/sources.cmake")
    include(generated/default/sources.cmake)
    set(FM2_GENERATED_SOURCES ${GENERATED_SOURCES})
endif()

macro(rexglue_setup_target target_name)
    target_sources(${target_name} PRIVATE ${FM2_GENERATED_SOURCES})
    target_include_directories(${target_name} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/generated/default
    )
    target_link_libraries(${target_name} PRIVATE rex::runtime)
    rexglue_configure_target(${target_name} ${ARGN})
endmacro()

add_custom_target(fm2_codegen
    COMMAND $<TARGET_FILE:rex::rexglue> codegen
        ${CMAKE_CURRENT_SOURCE_DIR}/fm2_manifest.toml
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Generating recompiled code for FM2"
    VERBATIM
)
