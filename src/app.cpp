#include "app.h"

#include <QCoreApplication>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSettings>

#include <cmath>

#include <windows.h>

namespace {

// What this run started with.
double startedScale = 1.0;
QString startedFont;

// The QML-side App object, once the engine has created it.
QPointer<App> appInstance;
bool activationPending = false;

// Usable before QCoreApplication exists, so the names are spelled out.
QSettings settings() { return QSettings(QStringLiteral("kleulir"), QStringLiteral("kleulir")); }

double savedScale() {
  const double scale = settings().value("appearance/scale", 1.0).toDouble();
  return scale >= 0.5 && scale <= 3.0 ? scale : 1.0;
}

QString savedFont() { return settings().value("appearance/font").toString(); }

}  // namespace

App::App(QObject* parent) : QObject(parent) {
  appInstance = this;
  // A launch that arrived before the UI existed.
  if (activationPending) {
    activationPending = false;
    QMetaObject::invokeMethod(this, &App::activationRequested, Qt::QueuedConnection);
  }
}

bool App::handOverToRunningInstance() {
  const QString name = QStringLiteral("kleulir-instance");

  QLocalSocket socket;
  socket.connectToServer(name);
  if (socket.waitForConnected(300)) {
    // Windows only lets the foreground process hand the foreground on.
    AllowSetForegroundWindow(ASFW_ANY);
    socket.write("show");
    socket.waitForBytesWritten(500);
    socket.disconnectFromServer();
    return true;
  }

  auto* server = new QLocalServer(QCoreApplication::instance());
  // Windows: a second server cannot take a name that is in use, so a race between
  // two launches leaves exactly one listener.
  server->setSocketOptions(QLocalServer::UserAccessOption);
  if (!server->listen(name)) return false;  // could not listen: just run
  QObject::connect(server, &QLocalServer::newConnection, server, [server] {
    while (QLocalSocket* client = server->nextPendingConnection()) {
      client->deleteLater();
      if (appInstance)
        emit appInstance->activationRequested();
      else
        activationPending = true;
    }
  });
  return false;
}

void App::applyScale() {
  startedScale = savedScale();
  // On top of the monitor's own scaling. An explicit QT_SCALE_FACTOR from outside wins.
  if (std::abs(startedScale - 1.0) > 0.001 && !qEnvironmentVariableIsSet("QT_SCALE_FACTOR"))
    qputenv("QT_SCALE_FACTOR", QByteArray::number(startedScale, 'f', 2));
}

void App::applyFont() {
  startedFont = savedFont();
  if (startedFont.isEmpty()) return;
  QFont font = QGuiApplication::font();
  font.setFamily(startedFont);
  QGuiApplication::setFont(font);
}

double App::uiScale() const { return savedScale(); }

void App::setUiScale(double scale) {
  if (std::abs(scale - savedScale()) < 0.001) return;
  settings().setValue("appearance/scale", scale);
  emit changed();
}

QString App::fontFamily() const { return savedFont(); }

void App::setFontFamily(const QString& family) {
  if (family == savedFont()) return;
  settings().setValue("appearance/font", family);
  emit changed();
}

QStringList App::fontFamilies() const {
  QStringList families;
  for (const QString& family : QFontDatabase::families()) {
    // Vertical-writing variants (@...) and private fonts are not for UI text.
    if (!family.startsWith('@') && !QFontDatabase::isPrivateFamily(family)) families << family;
  }
  return families;
}

bool App::restartRequired() const {
  return std::abs(savedScale() - startedScale) > 0.001 || savedFont() != startedFont;
}

bool App::closeToTray() const { return settings().value("tray/closeToTray", false).toBool(); }

void App::setCloseToTray(bool on) {
  if (on == closeToTray()) return;
  settings().setValue("tray/closeToTray", on);
  emit changed();
}

namespace {

QSettings runKey() {
  return QSettings(QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"),
                   QSettings::NativeFormat);
}

// What Windows runs at sign-in: this kleulir.exe, staying in the tray.
QString runCommand() {
  return QStringLiteral("\"%1\" --hidden").arg(QDir::toNativeSeparators(QCoreApplication::applicationFilePath()));
}

}  // namespace

// On only when the entry starts this very kleulir.exe: after the folder has been
// moved the old entry is stale, and turning the option on again rewrites it.
bool App::startWithWindows() const {
  return runKey().value(QStringLiteral("kleulir")).toString().compare(runCommand(), Qt::CaseInsensitive) == 0;
}

void App::setStartWithWindows(bool on) {
  if (on == startWithWindows()) return;
  QSettings key = runKey();
  if (on)
    key.setValue(QStringLiteral("kleulir"), runCommand());
  else
    key.remove(QStringLiteral("kleulir"));
  emit changed();
}

void App::restart() {
  QProcess::startDetached(QCoreApplication::applicationFilePath(), {});
  // exit(), not quit(): quit() asks the window to close, and with the tray option
  // on the window answers by hiding instead.
  QCoreApplication::exit(0);
}

namespace {

QString statePath(const QString& name) {
  QString safe = name;
  safe.removeIf([](QChar c) { return !c.isLetterOrNumber() && c != '-' && c != '_'; });
  const QString folder = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/state";
  QDir().mkpath(folder);
  return folder + "/" + safe + ".json";
}

}  // namespace

QString App::readState(const QString& name) const {
  QFile file(statePath(name));
  if (!file.open(QIODevice::ReadOnly)) return {};
  return QString::fromUtf8(file.readAll());
}

void App::writeState(const QString& name, const QString& text) const {
  QSaveFile file(statePath(name));
  if (!file.open(QIODevice::WriteOnly)) return;
  file.write(text.toUtf8());
  file.commit();
}
