#include "session.h"

#include <QCoreApplication>
#include <QJSEngine>
#include <QSettings>
#include <QSysInfo>
#include <QThreadPool>

#include "credentials.h"

using eos::client::Api;
using eos::client::Error;
using eos::client::Options;

namespace {

QString normalizedUrl(QString url) {
  url = url.trimmed();
  while (url.endsWith('/')) url.chop(1);
  if (!url.isEmpty() && !url.contains("://")) url.prepend("http://");
  return url;
}

Options optionsFor(const QString& url, const QString& key = {}) {
  Options o;
  o.base_url = url.toStdString();
  o.api_key = key.toStdString();
  o.client_name = "kleulir";
  return o;
}

QString message(const Error& e) {
  if (e.offline()) return QStringLiteral("Cannot reach the server.");
  if (e.unauthorized()) return QStringLiteral("Wrong username or password.");
  return QString::fromStdString(e.what());
}

}  // namespace

Session::Session(QObject* parent) : QObject(parent) {}

Session* Session::instance() {
  static Session* session = new Session(QCoreApplication::instance());
  return session;
}

Session* Session::create(QQmlEngine*, QJSEngine*) {
  QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
  return instance();
}

void Session::async(std::function<void()> work) {
  QThreadPool::globalInstance()->start(std::move(work));
}

void Session::onMain(std::function<void()> done) {
  QMetaObject::invokeMethod(QCoreApplication::instance(), std::move(done), Qt::QueuedConnection);
}

void Session::set(State state, const QString& error) {
  state_ = state;
  error_ = error;
  emit changed();
}

void Session::restore() {
  const QString url = QSettings().value("server/url").toString();
  serverUrl_ = url;
  if (url.isEmpty()) return;
  if (auto saved = credentials::load(url)) {
    restoring_ = true;
    // Until the server answers, assume what was true last time.
    eosFeatures_ = QSettings().value("server/eos", false).toBool();
    connectWithKey(url, saved->username, saved->key);
  } else {
    emit changed();
  }
}

void Session::retry() {
  if (state_ == Offline) restore();
}

void Session::login(const QString& serverUrl, const QString& username, const QString& password) {
  const QString url = normalizedUrl(serverUrl);
  if (url.isEmpty() || username.isEmpty() || password.isEmpty()) {
    set(LoggedOut, QStringLiteral("Enter the server address, username and password."));
    return;
  }
  serverUrl_ = url;
  restoring_ = false;
  set(Connecting);

  const QString device = QStringLiteral("kleulir (%1)").arg(QSysInfo::machineHostName());
  async([this, url, username, password, device] {
    try {
      const auto result =
          Api::login(optionsFor(url), username.toStdString(), password.toStdString(), device.toStdString());
      const QString key = QString::fromStdString(result.key);
      onMain([this, url, username, key] {
        QSettings().setValue("server/url", url);
        if (!credentials::save(url, {username, key}))
          qWarning("kleulir: could not store the API key in the Credential Manager");
        connectWithKey(url, username, key);
      });
    } catch (const Error& e) {
      const QString text = message(e);
      onMain([this, text] { set(LoggedOut, text); });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      onMain([this, text] { set(LoggedOut, text); });
    }
  });
}

void Session::connectWithKey(const QString& serverUrl, const QString& username, const QString& key) {
  serverUrl_ = serverUrl;
  username_ = username;
  set(Connecting);

  async([this, serverUrl, key] {
    auto api = std::make_shared<Api>(optionsFor(serverUrl, key));
    try {
      const auto user = api->user();
      bool eos = true;
      try {
        api->info();
      } catch (const Error& e) {
        if (e.offline()) throw;
        eos = false;  // a plain OpenSubsonic server has no /ext
      }
      onMain([this, api, user, eos] {
        api_ = api;
        username_ = QString::fromStdString(user.username);
        admin_ = user.admin;
        eosFeatures_ = eos;
        restoring_ = false;
        QSettings().setValue("server/eos", eos);
        set(Ready);
      });
    } catch (const Error& e) {
      const bool rejected = e.unauthorized();
      const QString text = rejected ? QStringLiteral("The saved key is no longer valid. Log in again.") : message(e);
      onMain([this, serverUrl, rejected, text] {
        api_.reset();
        restoring_ = false;
        if (rejected) credentials::remove(serverUrl);
        set(rejected ? LoggedOut : Offline, text);
      });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      onMain([this, text] {
        restoring_ = false;
        set(Offline, text);
      });
    }
  });
}

void Session::logout() {
  if (!serverUrl_.isEmpty()) credentials::remove(serverUrl_);
  api_.reset();
  username_.clear();
  admin_ = false;
  eosFeatures_ = false;
  restoring_ = false;
  set(LoggedOut);
}
