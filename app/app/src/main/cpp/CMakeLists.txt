project(Octo4a)
cmake_minimum_required(VERSION 3.4.1)

# Align segments to 16 KB so the libraries load on 16 KB page devices (Android 15+)
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

add_library(vsp-pty SHARED
            vsp-pty.cpp openpty.c)

target_link_libraries(vsp-pty
                      android
                      log)

add_library(yuv2rgb SHARED
            yuv2rgb.cpp)

target_link_libraries(yuv2rgb
                      android)

add_library(ioctl-hook SHARED
            ioctl-hook.c)

target_link_libraries(ioctl-hook
                      android)