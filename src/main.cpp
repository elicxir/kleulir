#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>

int main(int argc, char* argv[]) {
  QGuiApplication app(argc, argv);
  QGuiApplication::setApplicationName("kleulir");
  QGuiApplication::setOrganizationName("kleulir");

  QQmlApplicationEngine engine;
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
  engine.loadFromModule("Kleulir", "Main");

  // Development aid: KLEULIR_SCREENSHOT=<file.png> saves the window after it
  // has settled and exits, so a change can be checked without a person watching.
  const QString shot = qEnvironmentVariable("KLEULIR_SCREENSHOT");
  if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
    if (auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst())) {
      QTimer::singleShot(1500, window, [window, shot] {
        window->grabWindow().save(shot);
        QCoreApplication::quit();
      });
    }
  }

  return QGuiApplication::exec();
}
