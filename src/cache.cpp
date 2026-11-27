#include "cache.h"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>
#include <vector>

namespace cache {

QString folder(const QString& serverUrl) {
  if (serverUrl.isEmpty()) return {};
  const QString id =
      QString::fromLatin1(QCryptographicHash::hash(serverUrl.toUtf8(), QCryptographicHash::Sha1).toHex().left(12));
  const QString path = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/" + id;
  QDir().mkpath(path);
  return path;
}

QByteArray read(const QString& path) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) return {};
  return file.readAll();
}

bool write(const QString& path, const QByteArray& data) {
  QDir().mkpath(QFileInfo(path).absolutePath());
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly)) return false;
  file.write(data);
  return file.commit();
}

void prune(const QString& folder, qint64 maxBytes) {
  if (folder.isEmpty()) return;
  std::vector<QFileInfo> files;
  qint64 total = 0;
  for (QDirIterator it(folder, QDir::Files, QDirIterator::Subdirectories); it.hasNext();) {
    files.push_back(it.nextFileInfo());
    total += files.back().size();
  }
  if (total <= maxBytes) return;
  std::sort(files.begin(), files.end(),
            [](const QFileInfo& a, const QFileInfo& b) { return a.lastRead() < b.lastRead(); });
  for (const QFileInfo& f : files) {
    if (total <= maxBytes) break;
    if (QFile::remove(f.absoluteFilePath())) total -= f.size();
  }
}

}  // namespace cache
