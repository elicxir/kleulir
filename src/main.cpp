#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTimer>

#include <QIcon>

#include "app.h"
#include "coverprovider.h"
#include "session.h"

int main(int argc, char* argv[]) {
  // The display scale has to be in place before Qt creates anything.
  App::applyScale();

  QGuiApplication app(argc, argv);
  QGuiApplication::setApplicationName("kleulir");
  QGuiApplication::setOrganizationName("kleulir");
  QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/Kleulir/assets/kleulir.svg")));
  App::applyFont();

  // One kleulir per user: a second launch shows the first one's window and exits.
  // (Screenshot runs are separate, so a check can run beside the real app.)
  if (qEnvironmentVariableIsEmpty("KLEULIR_SCREENSHOT") && App::handOverToRunningInstance()) return 0;
  // With the tray option on, the app outlives its window.
  QGuiApplication::setQuitOnLastWindowClosed(false);

  // The UI is dark only; this also makes Windows draw a dark title bar.
  QGuiApplication::styleHints()->setColorScheme(Qt::ColorScheme::Dark);

  // Reconnect with the key saved for the last server before the UI is built, so the
  // first frame already knows a session is on its way and skips the login page.
  Session::instance()->restore();

  QQmlApplicationEngine engine;
  engine.addImageProvider(QStringLiteral("cover"), new CoverProvider);
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
  engine.loadFromModule("Kleulir", "Main");

  // Development aid: KLEULIR_SCREENSHOT=<file.png> saves the window after it
  // has settled and exits, so a change can be checked without a person watching.
  const QString shot = qEnvironmentVariable("KLEULIR_SCREENSHOT");
  if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
    auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst());
    if (window) {
      const int delay = qEnvironmentVariableIntValue("KLEULIR_SCREENSHOT_DELAY");
      QTimer::singleShot(delay > 0 ? delay : 1500, window, [window, shot] {
        window->grabWindow().save(shot);
        QCoreApplication::exit(0);
      });
    }
  }

  return QGuiApplication::exec();
}
