cmake_minimum_required(VERSION 3.10)
project(native_connectivity LANGUAGES CXX)

set(PLUGIN_NAME "native_connectivity_plugin")
find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

add_library(${PLUGIN_NAME} SHARED connectivity_monitor_plugin.cc)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK PkgConfig::GIO)

set(native_connectivity_bundled_libraries "" PARENT_SCOPE)
