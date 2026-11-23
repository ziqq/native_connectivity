cmake_minimum_required(VERSION 3.14)
project(native_connectivity LANGUAGES CXX)

set(PLUGIN_NAME "native_connectivity_plugin")
add_library(${PLUGIN_NAME} SHARED connectivity_monitor_plugin_c_api.cpp)
apply_standard_settings(${PLUGIN_NAME})
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
if("$ENV{NATIVE_CONNECTIVITY_TEST_FAIL_INTERFACE}" STREQUAL "1")
  target_compile_definitions(${PLUGIN_NAME} PRIVATE "$<$<CONFIG:Debug>:NATIVE_CONNECTIVITY_TEST_FAIL_INTERFACE>")
endif()
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin iphlpapi)

set(native_connectivity_bundled_libraries "" PARENT_SCOPE)
