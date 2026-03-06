set(TARGET llama-ignite-npu)
add_executable(${TARGET} ignite-npu.cpp)

option(IGNITE_USE_SYSTEM_DVFS "Use system DVFS library" ON)
if(IGNITE_USE_SYSTEM_DVFS)
    target_compile_definitions(${TARGET} PRIVATE IGNITE_USE_SYSTEM_DVFS)
endif()

target_link_libraries(${TARGET} PRIVATE common llama dvfs ${CMAKE_THREAD_LIBS_INIT})
target_compile_features(${TARGET} PRIVATE cxx_std_17)
if(LLAMA_TOOLS_INSTALL)
    install(TARGETS ${TARGET} RUNTIME)
endif()