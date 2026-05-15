cmake_minimum_required(VERSION 3.22)

# ---------------------------------------------------------------------------
# Cordial VST — Phase 1 scaffold
#
# Builds a MIDI-effect plugin (VST3 on Windows/Linux, AU on macOS) that emits
# a hardcoded C-major chord on bar 1. The chord notes themselves are fetched
# from a Lua script (`lua/host_vst.lua`) embedded as a binary resource, which
# proves the JUCE <-> sol2 <-> Lua 5.4 plumbing end-to-end. Phase 2 expands
# that Lua module into the host-agnostic `core/` extracted from `cordial.lua`.
#
# Dependencies are fetched by CPM at configure time; nothing is vendored in
# the repo. Out-of-source builds only.
# ---------------------------------------------------------------------------

project(CordialVST VERSION 0.0.1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Universal binaries on macOS so one build covers Intel + Apple Silicon.
if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "" FORCE)
endif()

include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/CPM.cmake)

# --- JUCE 8 ---------------------------------------------------------------
CPMAddPackage(
    NAME JUCE
    GITHUB_REPOSITORY juce-framework/JUCE
    GIT_TAG 8.0.4
    EXCLUDE_FROM_ALL YES
    SYSTEM YES
)

# --- Lua 5.4 (community CMake wrapper around the canonical source) --------
CPMAddPackage(
    NAME lua
    GITHUB_REPOSITORY walterschell/Lua
    GIT_TAG v5.4.5
    EXCLUDE_FROM_ALL YES
    SYSTEM YES
    OPTIONS
        "LUA_BUILD_BINARY OFF"
        "LUA_BUILD_COMPILER OFF"
        "LUA_SUPPORT_DL OFF"
)

# --- sol2 (header-only C++ <-> Lua binding) -------------------------------
CPMAddPackage(
    NAME sol2
    GITHUB_REPOSITORY ThePhD/sol2
    GIT_TAG v3.3.1
    EXCLUDE_FROM_ALL YES
    SYSTEM YES
    DOWNLOAD_ONLY YES
)
add_library(sol2 INTERFACE)
target_include_directories(sol2 SYSTEM INTERFACE ${sol2_SOURCE_DIR}/include)

# --- Plugin target --------------------------------------------------------
juce_add_plugin(CordialVST
    COMPANY_NAME            "Cordial"
    BUNDLE_ID               "com.cordial.vst"
    PLUGIN_MANUFACTURER_CODE Crdl
    PLUGIN_CODE             Cdvs
    FORMATS                 VST3 AU Standalone
    PRODUCT_NAME            "Cordial"
    IS_MIDI_EFFECT          TRUE
    NEEDS_MIDI_INPUT        TRUE
    NEEDS_MIDI_OUTPUT       TRUE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
    COPY_PLUGIN_AFTER_BUILD FALSE
)

juce_generate_juce_header(CordialVST)

# Embed Lua sources as JUCE BinaryData so the plugin is self-contained.
juce_add_binary_data(CordialVST_LuaData
    SOURCES
        lua/host_vst.lua
)

target_sources(CordialVST PRIVATE
    source/PluginProcessor.cpp
    source/PluginProcessor.h
    source/PluginEditor.cpp
    source/PluginEditor.h
    source/LuaHost.cpp
    source/LuaHost.h
)

target_compile_definitions(CordialVST PRIVATE
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_DISPLAY_SPLASH_SCREEN=0
)

target_link_libraries(CordialVST PRIVATE
    CordialVST_LuaData
    juce::juce_audio_utils
    lua_static
    sol2
    juce::juce_recommended_config_flags
    juce::juce_recommended_lto_flags
    juce::juce_recommended_warning_flags
)

# sol2 + Lua 5.4: opt into safe defaults that play nicely with modern C++.
target_compile_definitions(CordialVST PRIVATE
    SOL_ALL_SAFETIES_ON=1
    SOL_PRINT_ERRORS=0
)
