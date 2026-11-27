cmake_minimum_required(VERSION 3.25)
project(kleulir VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.8)

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
)

target_link_libraries(kleulir PRIVATE Qt6::Quick Qt6::QuickControls2)

# Running from the build tree: point Qt at vcpkg's plugins and QML modules.
# A packaged build will ship its own copies instead (windeployqt).
if(DEFINED VCPKG_INSTALLED_DIR)
  set(_qt_root "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/$<$<CONFIG:Debug>:debug/>Qt6")
  file(GENERATE
    OUTPUT "$<TARGET_FILE_DIR:kleulir>/qt.conf"
    CONTENT "[Paths]\nPrefix = ${_qt_root}\nPlugins = plugins\nQmlImports = qml\n"
  )
endif()
