// Session: which server we talk to and as whom. Owns the eos::client::Api that the
// rest of the backend shares.
#pragma once

#include <QMutex>
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
  // serverUrl() and api() may be called from any thread; the rest is for the main thread.
  QString serverUrl() const;
  QString username() const { return username_; }
  bool admin() const { return admin_; }
  bool eosFeatures() const { return eosFeatures_; }
  QStringList serverFeatures() const { return serverFeatures_; }
  Q_INVOKABLE bool hasFeature(const QString& name) const { return serverFeatures_.contains(name); }
  QString error() const { return error_; }
  bool restoring() const { return restoring_; }

  // Null unless state() == Ready.
  std::shared_ptr<eos::client::Api> api() const;

  // Reconnects with the key saved for the last server, if there is one.
  void restore();

  // Trades the password for a per-device API key and stores the key. On a plain
  // OpenSubsonic server, which has no keys, a Subsonic token and its salt are
  // stored instead. The password itself is not kept either way.
  Q_INVOKABLE void login(const QString& serverUrl, const QString& username, const QString& password);
  Q_INVOKABLE void logout();
  Q_INVOKABLE void retry();

  // Runs `work` on a worker thread and `done` back on the Qt main thread. The
  // workers are kleulir's own: a call still waiting for the server when the app
  // quits is left behind instead of holding the exit up.
  static void async(std::function<void()> work);
  static void onMain(std::function<void()> done);

 signals:
  void changed();

 private:
  explicit Session(QObject* parent = nullptr);
  void connectWithKey(const QString& serverUrl, const QString& username, const QString& key);
  void set(State state, const QString& error = {});
  void setApi(std::shared_ptr<eos::client::Api> api);
  void setServerUrl(const QString& url);

  State state_ = LoggedOut;
  QString serverUrl_, username_, error_;
  bool admin_ = false;
  bool eosFeatures_ = false;
  QStringList serverFeatures_;
  bool restoring_ = false;
  std::shared_ptr<eos::client::Api> api_;
  mutable QMutex mutex_;  // guards api_ and serverUrl_ for readers on other threads
  int attempt_ = 0;       // bumped per login, reconnect and logout; drops answers of an earlier one
};
