cmake_minimum_required(VERSION 3.25)
project(kleulir VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Packaged layout is flat: the DLLs sit next to kleulir.exe rather than in bin/.
# Qt's deploy support reads this when Qt is found, so it must be set first.
set(CMAKE_INSTALL_BINDIR ".")

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.8)

# libeos: the UI-less client library shared with the other eos clients.
add_subdirectory(external/eos/client/libeos)

qt_add_executable(kleulir WIN32
  src/main.cpp
)

# Singletons. Player and MockData stand in for libeos until it exists;
# the pages only talk to these two, so swapping them for C++ types later
# does not touch the screens.
set_source_files_properties(
  qml/Theme.qml
  qml/Player.qml
  qml/MockData.qml
  PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(kleulir
  URI Kleulir
  VERSION 1.0
  SOURCES
    src/session.h src/session.cpp
    src/library.h src/library.cpp
    src/coverprovider.h src/coverprovider.cpp
    src/credentials.h src/credentials.cpp
    src/audio.h src/audio.cpp
  QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/Player.qml
    qml/MockData.qml
    qml/Sidebar.qml
    qml/PlayerBar.qml
    qml/QueuePanel.qml
    qml/Cover.qml
    qml/Icon.qml
    qml/IconButton.qml
    qml/AlbumsPage.qml
    qml/AlbumPage.qml
    qml/PlaceholderPage.qml
    qml/SettingsPage.qml
    qml/LoginPage.qml
)

target_include_directories(kleulir PRIVATE src)
target_link_libraries(kleulir PRIVATE Qt6::Quick Qt6::QuickControls2 eos::client advapi32 WindowsApp)
# C++/WinRT headers (Windows SDK) for the system media player.
target_compile_options(kleulir PRIVATE /bigobj)

# Running from the build tree: point Qt at vcpkg's plugins and QML modules.
# A packaged build will ship its own copies instead (windeployqt).
if(DEFINED VCPKG_INSTALLED_DIR)
  set(_qt_root "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/$<$<CONFIG:Debug>:debug/>Qt6")
  file(GENERATE
    OUTPUT "$<TARGET_FILE_DIR:kleulir>/qt.conf"
    CONTENT "[Paths]\nPrefix = ${_qt_root}\nPlugins = plugins\nQmlImports = qml\n"
  )
endif()

# Packaging: `cmake --install build --config Release --prefix dist/kleulir` gathers the
# executable, the Qt libraries, plugins and QML modules it needs, and the other DLLs
# (libcurl and friends) into one folder that runs from anywhere.
install(TARGETS kleulir RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# DLLs that only Qt plugins depend on are not picked up by either tool: the JPEG
# image plugin (cover art) needs libjpeg.
if(DEFINED VCPKG_INSTALLED_DIR)
  install(FILES "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/bin/jpeg62.dll"
          DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
qt_generate_deploy_qml_app_script(
  TARGET kleulir
  OUTPUT_SCRIPT kleulir_deploy_script
  NO_UNSUPPORTED_PLATFORM_ERROR
  NO_TRANSLATIONS
  DEPLOY_TOOL_OPTIONS --no-compiler-runtime --no-system-d3d-compiler --no-opengl-sw
)
install(SCRIPT ${kleulir_deploy_script})
