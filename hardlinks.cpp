#include <cerrno>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <map>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <openssl/evp.h>

namespace fs = std::filesystem;

struct FileEntry {
    std::string path;
    dev_t dev;   // устройство (файловая система)
    ino_t ino;   // номер inode
    std::string hash;
};

// Вычисление SHA1 содержимого файла через open()/read()/close()
static bool sha1File(const std::string& path, std::string& hash)
{
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        std::cerr << path << ": " << strerror(errno) << std::endl;
        return false;
    }

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx || EVP_DigestInit_ex(ctx, EVP_sha1(), nullptr) != 1) {
        std::cerr << path << ": SHA1 initialization failed" << std::endl;
        EVP_MD_CTX_free(ctx);
        close(fd);
        return false;
    }

    std::vector<unsigned char> buf(65536);
    ssize_t n;
    bool ok = true;
    while ((n = read(fd, buf.data(), buf.size())) > 0) {
        if (EVP_DigestUpdate(ctx, buf.data(), n) != 1) {
            ok = false;
            break;
        }
    }
    if (n < 0) {
        std::cerr << path << ": " << strerror(errno) << std::endl;
        ok = false;
    }

    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int len = 0;
    if (ok && EVP_DigestFinal_ex(ctx, md, &len) != 1)
        ok = false;
    if (!ok && n >= 0)
        std::cerr << path << ": SHA1 computation failed" << std::endl;
    EVP_MD_CTX_free(ctx);
    close(fd);

    if (ok)
        hash.assign(reinterpret_cast<char*>(md), len);
    return ok;
}

// Атомарная замена файла жёсткой ссылкой:
// ссылка создаётся под временным именем, затем rename() заменяет дубликат
static bool replaceWithLink(const std::string& orig, const std::string& dup)
{
    // подбираем свободное временное имя: link() не перезаписывает существующие файлы
    std::string tmp;
    for (int i = 0; ; i++) {
        tmp = dup + ".tmplink" + std::to_string(i);
        if (link(orig.c_str(), tmp.c_str()) == 0)
            break;
        if (errno != EEXIST || i >= 1000) {
            std::cerr << "link " << tmp << " -> " << orig << ": " << strerror(errno) << std::endl;
            return false;
        }
    }
    if (rename(tmp.c_str(), dup.c_str()) != 0) {
        std::cerr << "rename " << tmp << " -> " << dup << ": " << strerror(errno) << std::endl;
        unlink(tmp.c_str());
        return false;
    }
    return true;
}

int main(int argc, char* argv[])
{
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <directory>" << std::endl;
        return 1;
    }

    std::error_code ec;
    if (!fs::is_directory(argv[1], ec)) {
        std::cerr << argv[1] << ": not a directory" << std::endl;
        return 2;
    }

    bool errors = false;

    // 1. Обход всего каталога и составление списка файлов
    std::vector<FileEntry> files;
    fs::recursive_directory_iterator it(argv[1], fs::directory_options::skip_permission_denied, ec);
    for (; !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
        // symlink_status: символьные ссылки не разыменовываются и пропускаются
        if (it->symlink_status().type() != fs::file_type::regular)
            continue;

        const std::string path = it->path().string();
        struct stat st;
        if (lstat(path.c_str(), &st) != 0) {
            std::cerr << path << ": " << strerror(errno) << std::endl;
            errors = true;
            continue;
        }
        files.push_back({path, st.st_dev, st.st_ino, ""});
    }
    if (ec) {
        std::cerr << argv[1] << ": " << ec.message() << std::endl;
        errors = true;
    }

    // 2. Вычисление SHA1 для каждого файла;
    //    файлы с одинаковым хэшем на одном устройстве попадают в одну группу
    //    (жёсткую ссылку нельзя создать в другой файловой системе)
    std::map<std::pair<dev_t, std::string>, std::vector<FileEntry>> groups;
    size_t hashed = 0;
    for (auto& f : files) {
        if (!sha1File(f.path, f.hash)) {
            errors = true;
            continue;
        }
        groups[{f.dev, f.hash}].push_back(f);
        hashed++;
    }

    // 3. В каждой группе оставляем первый файл, остальные заменяем жёсткими ссылками на него
    size_t linked = 0;
    for (const auto& [key, group] : groups) {
        const FileEntry& orig = group[0];
        for (size_t i = 1; i < group.size(); i++) {
            const FileEntry& dup = group[i];

            if (dup.ino == orig.ino)
                continue; // уже жёсткая ссылка на тот же inode

            if (replaceWithLink(orig.path, dup.path)) {
                std::cout << dup.path << " -> " << orig.path << std::endl;
                linked++;
            } else {
                errors = true;
            }
        }
    }

    std::cout << "files: " << hashed << ", replaced with hard links: " << linked << std::endl;
    return errors ? 2 : 0;
}
