// App: application-wide preferences that are not about one server — display scale,
// font, and whether kleulir stays in the system tray.
//
// Scale and font are applied once at start-up (the scale has to be set before Qt
// creates its first window), so changing them asks for a restart.
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class App : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  Q_PROPERTY(double uiScale READ uiScale WRITE setUiScale NOTIFY changed)        // 1.0 = 100%
  Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY changed)  // "" = system default
  Q_PROPERTY(QStringList fontFamilies READ fontFamilies CONSTANT)
  // The saved scale or font differs from what this run started with.
  Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY changed)
  // Closing the window hides it to the tray instead of quitting.
  Q_PROPERTY(bool closeToTray READ closeToTray WRITE setCloseToTray NOTIFY changed)
  // Start with the window hidden (only with closeToTray).
  Q_PROPERTY(bool startInTray READ startInTray WRITE setStartInTray NOTIFY changed)

 public:
  explicit App(QObject* parent = nullptr);

  // Call before QGuiApplication is created.
  static void applyScale();
  // Call right after QGuiApplication is created.
  static void applyFont();

  // Only one kleulir runs per user. Returns true when another one is already
  // running: it has been asked to show its window, and this process should exit.
  // Otherwise this process becomes the one that listens for later launches.
  static bool handOverToRunningInstance();

  double uiScale() const;
  void setUiScale(double scale);
  QString fontFamily() const;
  void setFontFamily(const QString& family);
  QStringList fontFamilies() const;
  bool restartRequired() const;
  bool closeToTray() const;
  void setCloseToTray(bool on);
  bool startInTray() const;
  void setStartInTray(bool on);

  Q_INVOKABLE void restart();

  // Small state files under %LOCALAPPDATA% (the play queue). `name` is a plain
  // word; the text is whatever the caller wants back.
  Q_INVOKABLE QString readState(const QString& name) const;
  Q_INVOKABLE void writeState(const QString& name, const QString& text) const;

 signals:
  void changed();
  // kleulir was launched again: show the window that is already there.
  void activationRequested();
};
