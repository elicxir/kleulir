#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTimer>

#include "coverprovider.h"
#include "session.h"

int main(int argc, char* argv[]) {
  QGuiApplication app(argc, argv);
  QGuiApplication::setApplicationName("kleulir");
  QGuiApplication::setOrganizationName("kleulir");

  // The UI is dark only; this also makes Windows draw a dark title bar.
  QGuiApplication::styleHints()->setColorScheme(Qt::ColorScheme::Dark);

  QQmlApplicationEngine engine;
  engine.addImageProvider(QStringLiteral("cover"), new CoverProvider);
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
  engine.loadFromModule("Kleulir", "Main");

  // Reconnect with the key saved for the last server, if any.
  Session::instance()->restore();

  // Development aid: KLEULIR_SCREENSHOT=<file.png> saves the window after it
  // has settled and exits, so a change can be checked without a person watching.
  const QString shot = qEnvironmentVariable("KLEULIR_SCREENSHOT");
  if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
    if (auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst())) {
      const int delay = qEnvironmentVariableIntValue("KLEULIR_SCREENSHOT_DELAY");
      QTimer::singleShot(delay > 0 ? delay : 1500, window, [window, shot] {
        window->grabWindow().save(shot);
        QCoreApplication::quit();
      });
    }
  }

  return QGuiApplication::exec();
}
