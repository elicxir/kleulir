#include "mediakeys.h"

#include <QGuiApplication>
#include <QWindow>

#include <windows.h>

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include "session.h"

using namespace winrt;
using namespace winrt::Windows::Media;

namespace {
hstring hs(const QString& s) { return hstring(s.toStdWString()); }
}  // namespace

struct MediaKeys::Impl {
  SystemMediaTransportControls controls{nullptr};
  SystemMediaTransportControls::ButtonPressed_revoker pressed;
};

MediaKeys::MediaKeys(QObject* parent) : QObject(parent), impl_(std::make_unique<Impl>()) {}

MediaKeys::~MediaKeys() {
  if (!impl_->controls) return;
  impl_->pressed.revoke();
  try {
    impl_->controls.DisplayUpdater().ClearAll();
    impl_->controls.IsEnabled(false);
  } catch (const hresult_error&) {
  }
}

bool MediaKeys::ready() {
  if (impl_->controls) return true;

  // A desktop app gets its controls through one of its windows. A window hidden in
  // the tray still has a handle, so this works before the window is ever shown.
  const auto windows = QGuiApplication::topLevelWindows();
  if (windows.isEmpty()) return false;
  const HWND hwnd = reinterpret_cast<HWND>(windows.constFirst()->winId());
  if (!hwnd) return false;

  try {
    const auto interop = get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    check_hresult(interop->GetForWindow(hwnd, guid_of<SystemMediaTransportControls>(), put_abi(impl_->controls)));

    auto& controls = impl_->controls;
    controls.IsEnabled(true);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);

    // Arrives on a system thread.
    impl_->pressed = controls.ButtonPressed(
        auto_revoke,
        [this](SystemMediaTransportControls const&, SystemMediaTransportControlsButtonPressedEventArgs const& args) {
          const auto button = args.Button();
          Session::onMain([this, button] {
            switch (button) {
              case SystemMediaTransportControlsButton::Play:
                emit playRequested();
                break;
              case SystemMediaTransportControlsButton::Pause:
                emit pauseRequested();
                break;
              case SystemMediaTransportControlsButton::Next:
                emit nextRequested();
                break;
              case SystemMediaTransportControlsButton::Previous:
                emit previousRequested();
                break;
              default:
                break;
            }
          });
        });
    return true;
  } catch (const hresult_error&) {
    impl_->controls = nullptr;
    return false;
  }
}

void MediaKeys::setTrack(const QVariantMap& meta) {
  pendingTrack_ = meta;
  if (!ready()) return;
  try {
    auto updater = impl_->controls.DisplayUpdater();
    updater.ClearAll();
    updater.Type(MediaPlaybackType::Music);
    updater.MusicProperties().Title(hs(meta.value("title").toString()));
    updater.MusicProperties().Artist(hs(meta.value("artist").toString()));
    updater.MusicProperties().AlbumTitle(hs(meta.value("album").toString()));
    const QString cover = meta.value("coverUrl").toString();
    if (!cover.isEmpty()) {
      updater.Thumbnail(winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(
          winrt::Windows::Foundation::Uri(hs(cover))));
    }
    updater.Update();
  } catch (const hresult_error&) {
  }
}

void MediaKeys::setState(State state) {
  state_ = state;
  if (!ready()) return;
  try {
    impl_->controls.PlaybackStatus(state == Playing  ? MediaPlaybackStatus::Playing
                                   : state == Paused ? MediaPlaybackStatus::Paused
                                                     : MediaPlaybackStatus::Stopped);
    if (state == Stopped) {
      impl_->controls.DisplayUpdater().ClearAll();
      impl_->controls.DisplayUpdater().Update();
    }
  } catch (const hresult_error&) {
  }
}
