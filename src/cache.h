// On-disk cache under %LOCALAPPDATA%\kleulir\cache, one folder per server.
#pragma once

#include <QByteArray>
#include <QString>

namespace cache {

// Folder for `serverUrl` (created on demand). Empty when the URL is empty.
QString folder(const QString& serverUrl);

QByteArray read(const QString& path);
// Writes through a temporary file so a reader never sees half a file.
bool write(const QString& path, const QByteArray& data);

// Deletes the least recently used files of `folder` until it fits in `maxBytes`.
void prune(const QString& folder, qint64 maxBytes);

}  // namespace cache
