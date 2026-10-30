cmake_minimum_required(VERSION 3.14)
project(expert-log CXX)

# built llama.cpp tree, e.g. -DLLAMA_DIR=~/llama.cpp -DLLAMA_BUILD=~/llama.cpp/build
set(LLAMA_DIR   "$ENV{HOME}/llama.cpp" CACHE PATH "llama.cpp source tree")
set(LLAMA_BUILD "${LLAMA_DIR}/build"   CACHE PATH "llama.cpp build dir")

set(LLAMA_LIB_DIR "${LLAMA_BUILD}/bin")

add_executable(expert-log expert-log.cpp)
target_compile_features(expert-log PRIVATE cxx_std_17)
target_include_directories(expert-log PRIVATE
    ${LLAMA_DIR}/include
    ${LLAMA_DIR}/ggml/include
    ${LLAMA_DIR}/common)
target_link_directories(expert-log PRIVATE ${LLAMA_LIB_DIR})
target_link_libraries(expert-log PRIVATE llama-common llama ggml ggml-base)
set_target_properties(expert-log PROPERTIES BUILD_RPATH ${LLAMA_LIB_DIR})
