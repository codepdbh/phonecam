cmake_minimum_required(VERSION 3.15)
project(phonecam_virtual_camera LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_definitions(-DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

set(SOURCES
    src/synthetic_frame_generator.cpp
    src/phonecam_frame_converter.cpp
    src/phonecam_media_stream.cpp
    src/phonecam_media_source.cpp
    src/phonecam_media_source_activate.cpp
    src/phonecam_dshow_filter.cpp
    src/phonecam_ffi_exports.cpp
    src/exports.def
)

add_library(PhoneCamMediaSource SHARED ${SOURCES})

target_link_libraries(PhoneCamMediaSource PRIVATE
    mfplat
    mfuuid
    mf
    mfreadwrite
    mfsensorgroup
    strmiids
    ole32
    oleaut32
    uuid
    shlwapi
    runtimeobject
)

set_target_properties(PhoneCamMediaSource PROPERTIES
    OUTPUT_NAME "PhoneCamMediaSource_v7"
    PREFIX ""
)

# Standalone test runner for Phase 6
add_executable(PhoneCamTestRunner
    src/test_cam_runner.cpp
)

target_link_libraries(PhoneCamTestRunner PRIVATE
    PhoneCamMediaSource
)

add_executable(PhoneCamContractTest
    src/test_media_source_contract.cpp
)
target_link_libraries(PhoneCamContractTest PRIVATE
    mfplat
    mfuuid
    ole32
)

add_executable(PhoneCamFrameBrokerTest
    src/test_frame_broker.cpp
    src/phonecam_frame_converter.cpp
)

add_executable(PhoneCamCaptureTest
    src/test_virtual_camera_capture.cpp
)
target_link_libraries(PhoneCamCaptureTest PRIVATE
    mfplat
    mfuuid
    mf
    mfreadwrite
    ole32
)

add_executable(PhoneCamBrokerStats
    src/test_broker_stats.cpp
)
