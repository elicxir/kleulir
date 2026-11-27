#include "credentials.h"

#include <QByteArray>

#include <windows.h>

#include <wincred.h>

namespace credentials {

namespace {
std::wstring target(const QString& serverUrl) {
  return (QStringLiteral("kleulir/") + serverUrl).toStdWString();
}
}  // namespace

std::optional<Entry> load(const QString& serverUrl) {
  PCREDENTIALW cred = nullptr;
  if (!CredReadW(target(serverUrl).c_str(), CRED_TYPE_GENERIC, 0, &cred)) return std::nullopt;
  Entry entry;
  entry.username = QString::fromWCharArray(cred->UserName ? cred->UserName : L"");
  entry.key = QString::fromUtf8(reinterpret_cast<const char*>(cred->CredentialBlob),
                                static_cast<qsizetype>(cred->CredentialBlobSize));
  CredFree(cred);
  if (entry.key.isEmpty()) return std::nullopt;
  return entry;
}

bool save(const QString& serverUrl, const Entry& entry) {
  const std::wstring name = target(serverUrl);
  std::wstring user = entry.username.toStdWString();
  QByteArray blob = entry.key.toUtf8();

  CREDENTIALW cred = {};
  cred.Type = CRED_TYPE_GENERIC;
  cred.TargetName = const_cast<LPWSTR>(name.c_str());
  cred.UserName = user.data();
  cred.CredentialBlob = reinterpret_cast<LPBYTE>(blob.data());
  cred.CredentialBlobSize = static_cast<DWORD>(blob.size());
  cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
  return CredWriteW(&cred, 0) != FALSE;
}

void remove(const QString& serverUrl) {
  CredDeleteW(target(serverUrl).c_str(), CRED_TYPE_GENERIC, 0);
}

}  // namespace credentials
