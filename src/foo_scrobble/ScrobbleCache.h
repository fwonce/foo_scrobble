#pragma once
#include "Track.h"

#include <SDK/foobar2000.h>

#include <mutex>
#include <vector>

namespace foo_scrobble
{

class ScrobbleCache
{
public:
    static ScrobbleCache& Get()
    {
        static ScrobbleCache instance;
        return instance;
    }

    bool IsEmpty();
    size_t Count();
    Track operator[](size_t index);

    void Add(Track track);
    void Evict(size_t count);
    void EnsureLoaded();

private:
    ScrobbleCache() = default;
    void Load();
    void Save();
    std::string GetFilePath() const;

    mutable std::mutex mutex_;
    std::vector<Track> tracks_;
    bool loaded_ = false;
};

} // namespace foo_scrobble
