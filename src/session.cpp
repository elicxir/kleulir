#include "session.h"

#include <QCoreApplication>
#include <QJSEngine>
#include <QMutexLocker>
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

// What is kept in the Credential Manager for a plain OpenSubsonic server, which has
// no API keys: the Subsonic token and its salt (not the password), marked like this.
const QLatin1String kTokenMark("subsonic-token:");

QString tokenSecret(const eos::client::TokenLogin& login) {
  return kTokenMark + QString::fromStdString(login.salt) + QLatin1Char(':') + QString::fromStdString(login.token);
}

// `secret` is an eos API key, or a token as tokenSecret() writes it.
Options optionsFor(const QString& url, const QString& secret = {}, const QString& username = {}) {
  Options o;
  o.base_url = url.toStdString();
  o.client_name = "kleulir";
  if (secret.startsWith(kTokenMark)) {
    const QString rest = secret.mid(kTokenMark.size());
    const qsizetype colon = rest.indexOf(QLatin1Char(':'));
    o.username = username.toStdString();
    o.salt = rest.left(colon).toStdString();
    o.token = rest.mid(colon + 1).toStdString();
  } else {
    o.api_key = secret.toStdString();
  }
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
  // Never deleted: Qt waits for the global pool when the application object goes
  // away, and a request to a server that does not answer would hold the exit up
  // for its whole timeout.
  static QThreadPool* const pool = [] {
    auto* p = new QThreadPool;
    p->setMaxThreadCount(8);
    return p;
  }();
  pool->start(std::move(work));
}

void Session::onMain(std::function<void()> done) {
  // Null once the app is quitting: the answer has nowhere to go.
  if (QCoreApplication* app = QCoreApplication::instance())
    QMetaObject::invokeMethod(app, std::move(done), Qt::QueuedConnection);
}

QString Session::serverUrl() const {
  const QMutexLocker lock(&mutex_);
  return serverUrl_;
}

std::shared_ptr<Api> Session::api() const {
  const QMutexLocker lock(&mutex_);
  return api_;
}

void Session::setApi(std::shared_ptr<Api> api) {
  const QMutexLocker lock(&mutex_);
  api_ = std::move(api);
}

void Session::setServerUrl(const QString& url) {
  const QMutexLocker lock(&mutex_);
  serverUrl_ = url;
}

void Session::set(State state, const QString& error) {
  state_ = state;
  error_ = error;
  emit changed();
}

void Session::restore() {
  const QString url = QSettings().value("server/url").toString();
  setServerUrl(url);
  if (url.isEmpty()) return;
  if (auto saved = credentials::load(url)) {
    restoring_ = true;
    // Until the server answers, assume what was true last time.
    eosFeatures_ = QSettings().value("server/eos", false).toBool();
    serverFeatures_ = QSettings().value("server/features").toStringList();
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
  setServerUrl(url);
  restoring_ = false;
  const int attempt = ++attempt_;
  set(Connecting);

  const QString device = QStringLiteral("kleulir (%1)").arg(QSysInfo::machineHostName());
  async([this, url, username, password, device, attempt] {
    try {
      QString key, keyId;
      try {
        const auto result =
            Api::login(optionsFor(url), username.toStdString(), password.toStdString(), device.toStdString());
        key = QString::fromStdString(result.key);
        keyId = QString::fromStdString(result.id);
      } catch (const Error& e) {
        // Nothing is there at all, or eos itself says no (wrong password, too many
        // tries): an eos refusal comes with eos's own error body.
        if (e.offline() || e.kind() == Error::Kind::ext) throw;
        // Anything else (404, a web page, a redirect): not an eos server. Try it as
        // a plain OpenSubsonic one.
        key = tokenSecret(Api::token_login(optionsFor(url), username.toStdString(), password.toStdString()));
      }
      onMain([this, url, username, key, keyId, attempt] {
        if (attempt != attempt_) return;  // logged out, or another login started, meanwhile
        QSettings().setValue("server/url", url);
        QSettings().setValue("server/keyId", keyId);
        if (!credentials::save(url, {username, key}))
          qWarning("kleulir: could not store the API key in the Credential Manager");
        connectWithKey(url, username, key);
      });
    } catch (const Error& e) {
      const QString text = message(e);
      onMain([this, text, attempt] {
        if (attempt == attempt_) set(LoggedOut, text);
      });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      onMain([this, text, attempt] {
        if (attempt == attempt_) set(LoggedOut, text);
      });
    }
  });
}

void Session::connectWithKey(const QString& serverUrl, const QString& username, const QString& key) {
  setServerUrl(serverUrl);
  username_ = username;
  const int attempt = ++attempt_;
  set(Connecting);

  async([this, serverUrl, username, key, attempt] {
    auto api = std::make_shared<Api>(optionsFor(serverUrl, key, username));
    try {
      const auto user = api->user();
      bool eos = true;
      QStringList features;
      try {
        for (const auto& f : api->info().features) features.append(QString::fromStdString(f));
      } catch (const Error& e) {
        if (e.offline()) throw;
        eos = false;  // a plain OpenSubsonic server has no /ext
      }
      onMain([this, api, user, eos, features, attempt] {
        if (attempt != attempt_) return;
        setApi(api);
        username_ = QString::fromStdString(user.username);
        admin_ = user.admin;
        eosFeatures_ = eos;
        serverFeatures_ = features;
        restoring_ = false;
        QSettings().setValue("server/eos", eos);
        QSettings().setValue("server/features", features);
        set(Ready);
      });
    } catch (const Error& e) {
      const bool rejected = e.unauthorized();
      const QString text = rejected ? QStringLiteral("The saved key is no longer valid. Log in again.") : message(e);
      onMain([this, serverUrl, rejected, text, attempt] {
        if (attempt != attempt_) return;
        setApi(nullptr);
        restoring_ = false;
        if (rejected) credentials::remove(serverUrl);
        set(rejected ? LoggedOut : Offline, text);
      });
    } catch (const std::exception& e) {
      const QString text = QString::fromUtf8(e.what());
      onMain([this, text, attempt] {
        if (attempt != attempt_) return;
        restoring_ = false;
        set(Offline, text);
      });
    }
  });
}

void Session::logout() {
  ++attempt_;  // an answer still on its way must not log us back in
  if (!serverUrl_.isEmpty()) credentials::remove(serverUrl_);
  // The key is this device's own: tell the server it is no longer in use. Offline,
  // it stays valid there until it is revoked from another device.
  const QString keyId = QSettings().value("server/keyId").toString();
  QSettings().remove("server/keyId");
  if (const auto api = api_; api && !keyId.isEmpty()) {
    async([api, keyId] {
      try {
        api->revoke_api_key(keyId.toStdString());
      } catch (const std::exception&) {
      }
    });
  }
  setApi(nullptr);
  username_.clear();
  admin_ = false;
  eosFeatures_ = false;
  serverFeatures_.clear();
  restoring_ = false;
  set(LoggedOut);
}
