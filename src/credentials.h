// API keys in the Windows Credential Manager, one entry per server.
#pragma once

#include <QString>

#include <optional>

namespace credentials {

struct Entry {
  QString username;
  QString key;
};

std::optional<Entry> load(const QString& serverUrl);
bool save(const QString& serverUrl, const Entry& entry);
void remove(const QString& serverUrl);

}  // namespace credentials
