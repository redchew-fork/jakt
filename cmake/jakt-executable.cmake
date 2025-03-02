#
# Build rules to build a jakt executable using the configured C++ compiler
# Note this file is used to build jakt itself and installed for jakt projects to use
#

# FIXME: Should this live in a toolchain file?
set(JAKT_TARGET_IN "${CMAKE_SYSTEM_PROCESSOR}-unknown-${CMAKE_SYSTEM_NAME}-unknown")
STRING(TOLOWER ${JAKT_TARGET_IN} JAKT_TARGET)

function(add_jakt_compiler_flags target)
  target_compile_options("${target}" PRIVATE
    -Wno-unused-local-typedefs
    -Wno-unused-function
    -Wno-unused-variable
    -Wno-unused-parameter
    -Wno-unused-but-set-variable
    -Wno-unused-result
    -Wno-implicit-fallthrough # !!
    -Wno-trigraphs
    -Wno-parentheses-equality
    -Wno-unqualified-std-cast-call
    -Wno-user-defined-literals
    -Wno-return-type
    -Wno-deprecated-declarations
    -Wno-unknown-warning-option
    -Wno-unused-command-line-argument
    -fdiagnostics-color=always
  )
  if (MSVC)
    # For clang-cl, which shows up to CMake as MSVC and accepts both kinds of arguments
    target_compile_options("${target}" PRIVATE /permissive- /utf-8 /EHsc-)
  else()
    target_compile_options("${target}" PRIVATE -fno-exceptions)
  endif()
  if (CYGWIN OR MSYS)
    target_compile_options("${target}" PRIVATE -Wa,-mbig-obj)
  endif()
  target_compile_features("${target}" PRIVATE cxx_std_20)

  if (WIN32)
    cmake_policy(GET CMP0091 msvc_runtime_prop_enabled)
    if (NOT msvc_runtime_prop_enabled STREQUAL "NEW")
      message(WARNING "CMake Policy CMP0091 is not set to NEW, linker errors from jakt_runtime may result")
    endif()
    set_property(TARGET "${target}" PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  endif()
endfunction()

function(add_jakt_executable executable)
  cmake_parse_arguments(PARSE_ARGV 1 JAKT_EXECUTABLE "" "MAIN_SOURCE;RUNTIME_DIRECTORY;COMPILER" "MODULE_SOURCES;STDLIB_SOURCES;INCLUDES")
  set(main_source "${CMAKE_CURRENT_LIST_DIR}/${JAKT_EXECUTABLE_MAIN_SOURCE}" )
  set(runtime_path "${CMAKE_CURRENT_LIST_DIR}/runtime" )
  get_filename_component(main_base "${main_source}" NAME_WE)

  list(APPEND cpp_files "Root Module.cpp")
  foreach (file ${JAKT_EXECUTABLE_STDLIB_SOURCES})
      list(APPEND cpp_files "${file}")
  endforeach()

  foreach(module_source ${JAKT_EXECUTABLE_MODULE_SOURCES})
    get_filename_component(module_base "${module_source}" NAME_WE)
    list(APPEND cpp_files "${module_base}.cpp")
  endforeach()

  if (NOT JAKT_EXECUTABLE_COMPILER)
    set(JAKT_EXECUTABLE_COMPILER Jakt::jakt)
  endif()

  if (NOT JAKT_EXECUTABLE_RUNTIME_DIRECTORY)
    set(JAKT_EXECUTABLE_COMPILER_INCLUDES "$<TARGET_PROPERTY:${JAKT_EXECUTABLE_COMPILER},INTERFACE_INCLUDE_DIRECTORIES>")
  else()
    set(JAKT_EXECUTABLE_COMPILER_INCLUDES "${JAKT_EXECUTABLE_RUNTIME_DIRECTORY}")
  endif()

  list(APPEND JAKT_EXECUTABLE_COMPILER_INCLUDES ${JAKT_EXECUTABLE_INCLUDES})
  list(PREPEND JAKT_EXECUTABLE_COMPILER_INCLUDES .)
  list(REMOVE_DUPLICATES JAKT_EXECUTABLE_COMPILER_INCLUDES)

  set(binary_tmp_dir "${CMAKE_CURRENT_BINARY_DIR}/${executable}_tmp")
  list(TRANSFORM cpp_files PREPEND "${binary_tmp_dir}/")

  file(MAKE_DIRECTORY "${binary_tmp_dir}")

  add_custom_command(
    OUTPUT ${cpp_files}
    COMMAND "$<TARGET_FILE:${JAKT_EXECUTABLE_COMPILER}>"
      -S
      $<$<CONFIG:Release>:-O>
      -T "${JAKT_TARGET}"
      --binary-dir "${binary_tmp_dir}"
      --runtime-path "${runtime_path}"
      -I "$<JOIN:${JAKT_EXECUTABLE_COMPILER_INCLUDES},;-I>"
      "${main_source}"
    VERBATIM
    COMMENT "Building jakt file ${JAKT_EXECUTABLE_MAIN_SOURCE} with ${JAKT_EXECUTABLE_COMPILER}"
    MAIN_DEPENDENCY "${main_source}"
    DEPENDS ${JAKT_EXECUTABLE_MODULE_SOURCES}
    COMMAND_EXPAND_LISTS
  )
  add_custom_target("generate_${executable}" DEPENDS ${cpp_files})

  add_executable("${executable}")
  foreach(file ${cpp_files})
    target_sources("${executable}" PRIVATE "${file}")
    set_source_files_properties("${file}" PROPERTIES GENERATED TRUE)
  endforeach()

  add_jakt_compiler_flags("${executable}")

  target_link_libraries("${executable}" PRIVATE Jakt::jakt_main)
  target_link_libraries("${executable}" PRIVATE Jakt::jakt_runtime)
  add_dependencies("${executable}" "generate_${executable}")
endfunction()
