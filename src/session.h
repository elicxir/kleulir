// Session: which server we talk to and as whom. Owns the eos::client::Api that the
// rest of the backend shares.
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

#include <functional>
#include <memory>

#include <eos/client/api.h>

class QQmlEngine;
class QJSEngine;

class Session : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  Q_PROPERTY(State state READ state NOTIFY changed)
  Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY changed)
  Q_PROPERTY(QString username READ username NOTIFY changed)
  Q_PROPERTY(bool admin READ admin NOTIFY changed)
  // false on a plain OpenSubsonic server: no /ext, so no folders, works or sync.
  Q_PROPERTY(bool eosFeatures READ eosFeatures NOTIFY changed)
  // What GET /ext/info lists (graph, similarity, ...); empty on a plain server.
  Q_PROPERTY(QStringList serverFeatures READ serverFeatures NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)
  // true while reconnecting with a saved key: the UI shows the library (from its
  // cache) instead of the login page.
  Q_PROPERTY(bool restoring READ restoring NOTIFY changed)

 public:
  enum State { LoggedOut, Connecting, Ready, Offline };
  Q_ENUM(State)

  static Session* instance();
  static Session* create(QQmlEngine*, QJSEngine*);

  State state() const { return state_; }
  QString serverUrl() const { return serverUrl_; }
  QString username() const { return username_; }
  bool admin() const { return admin_; }
  bool eosFeatures() const { return eosFeatures_; }
  QStringList serverFeatures() const { return serverFeatures_; }
  Q_INVOKABLE bool hasFeature(const QString& name) const { return serverFeatures_.contains(name); }
  QString error() const { return error_; }
  bool restoring() const { return restoring_; }

  // Null unless state() == Ready.
  std::shared_ptr<eos::client::Api> api() const { return api_; }

  // Reconnects with the key saved for the last server, if there is one.
  void restore();

  // Trades the password for a per-device API key and stores the key. The password
  // itself is not kept.
  Q_INVOKABLE void login(const QString& serverUrl, const QString& username, const QString& password);
  Q_INVOKABLE void logout();
  Q_INVOKABLE void retry();

  // Runs `work` on a worker thread and `done` back on the Qt main thread.
  static void async(std::function<void()> work);
  static void onMain(std::function<void()> done);

 signals:
  void changed();

 private:
  explicit Session(QObject* parent = nullptr);
  void connectWithKey(const QString& serverUrl, const QString& username, const QString& key);
  void set(State state, const QString& error = {});

  State state_ = LoggedOut;
  QString serverUrl_, username_, error_;
  bool admin_ = false;
  bool eosFeatures_ = false;
  QStringList serverFeatures_;
  bool restoring_ = false;
  std::shared_ptr<eos::client::Api> api_;
};
