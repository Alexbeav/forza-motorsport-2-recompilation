cmake_minimum_required(VERSION 3.25)
project(fm2_host_tests LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
enable_testing()
add_executable(content_status_test content_status_test.cpp)
target_include_directories(content_status_test PRIVATE ../fm2/src)
add_test(NAME content_status COMMAND content_status_test)

# Point at an SDK tree with release/sdk-fps-cap.patch applied.
if(FPS_CAP_SDK_ROOT)
    if(WIN32 AND NOT CMAKE_BUILD_TYPE STREQUAL "Release")
        message(FATAL_ERROR "The FPS-cap fixture links a Release SDK. Configure with -G Ninja -DCMAKE_BUILD_TYPE=Release.")
    endif()
    add_executable(frame_pacer_test frame_pacer_test.cpp)
    target_include_directories(frame_pacer_test PRIVATE "${FPS_CAP_SDK_ROOT}/src/graphics" "${FPS_CAP_SDK_ROOT}/include")
    if(WIN32)
        target_link_libraries(frame_pacer_test PRIVATE "${FPS_CAP_SDK_ROOT}/out/win-amd64/Release/rexruntime.lib")
        add_custom_command(TARGET frame_pacer_test POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${FPS_CAP_SDK_ROOT}/out/win-amd64/Release/rexruntime.dll"
                "${FPS_CAP_SDK_ROOT}/out/win-amd64/Release/TracyClient.dll"
                "${FPS_CAP_SDK_ROOT}/out/win-amd64/Release/rexgpu-xenos.dll"
                "$<TARGET_FILE_DIR:frame_pacer_test>")
    endif()
    add_test(NAME frame_pacer COMMAND frame_pacer_test)
endif()
