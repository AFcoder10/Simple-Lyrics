cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "media_bridge.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "window_bridge.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# The Global System Media Transport Controls API used by media_bridge.cpp
# requires Windows 10 1809 or newer.
target_compile_definitions(${BINARY_NAME} PRIVATE "_WIN32_WINNT=0x0A00" "WINVER=0x0A00")

# C++/WinRT pulls the coroutine headers in via <winrt/base.h>, which MSVC flags
# under C++17. Silence the deprecation as MSVC itself recommends. Building as
# C++20 is not an option: cppwinrt's delegate templates do not compile there.
target_compile_definitions(${BINARY_NAME} PRIVATE "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")

# C++/WinRT propagates HRESULT failures through exceptions, but Flutter's
# standard settings compile the runner with exceptions disabled. Re-enable them
# for the runner target only, leaving plugin targets untouched.
get_target_property(runner_definitions ${BINARY_NAME} COMPILE_DEFINITIONS)
if(runner_definitions)
  list(REMOVE_ITEM runner_definitions "_HAS_EXCEPTIONS=0")
  set_target_properties(${BINARY_NAME} PROPERTIES COMPILE_DEFINITIONS "${runner_definitions}")
endif()

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# Required to activate WinRT classes such as
# Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.
target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
