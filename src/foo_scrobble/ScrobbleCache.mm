#include "ScrobbleCache.h"

#import <Foundation/Foundation.h>

namespace foo_scrobble
{

void ScrobbleCache::EnsureLoaded()
{
    // Must be called with services available (not during static init)
    if (loaded_) return;

    std::lock_guard lock(mutex_);
    if (loaded_) return;
    loaded_ = true;

    std::string path = GetFilePath();
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSData* data = [NSData dataWithContentsOfFile:nsPath];
    if (!data) return;

    @try {
        NSError* error = nil;
        NSArray* array = [NSJSONSerialization JSONObjectWithData:data
                                                        options:0
                                                          error:&error];
        if (error || ![array isKindOfClass:[NSArray class]])
            return;

        tracks_.clear();
        tracks_.reserve(array.count);

        for (NSDictionary* dict in array) {
            if (![dict isKindOfClass:[NSDictionary class]])
                continue;

            Track track;
            NSNumber* timestamp = dict[@"timestamp"];
            if (timestamp)
                track.Timestamp = unix_clock::from_time_t(timestamp.longLongValue);

            NSString* artist = dict[@"artist"];
            if (artist) track.Artist = [artist UTF8String];
            NSString* title = dict[@"title"];
            if (title) track.Title = [title UTF8String];
            NSString* albumArtist = dict[@"albumArtist"];
            if (albumArtist) track.AlbumArtist = [albumArtist UTF8String];
            NSString* album = dict[@"album"];
            if (album) track.Album = [album UTF8String];
            NSString* trackNumber = dict[@"trackNumber"];
            if (trackNumber) track.TrackNumber = [trackNumber UTF8String];
            NSString* mbid = dict[@"mbid"];
            if (mbid) track.MusicBrainzId = [mbid UTF8String];
            NSNumber* duration = dict[@"duration"];
            if (duration)
                track.Duration = std::chrono::duration<double>(duration.doubleValue);
            NSNumber* isDynamic = dict[@"isDynamic"];
            if (isDynamic) track.IsDynamic = isDynamic.boolValue;

            if (track.IsValid())
                tracks_.push_back(std::move(track));
        }
    } @catch (...) {}
}

std::string ScrobbleCache::GetFilePath() const
{
    pfc::string8 profilePath = core_api::get_profile_path();
    std::string path = profilePath.c_str();
    path += "/foo_scrobble_cache.json";
    return path;
}

bool ScrobbleCache::IsEmpty()
{
    EnsureLoaded();
    std::lock_guard lock(mutex_);
    return tracks_.empty();
}

size_t ScrobbleCache::Count()
{
    EnsureLoaded();
    std::lock_guard lock(mutex_);
    return tracks_.size();
}

Track ScrobbleCache::operator[](size_t index)
{
    EnsureLoaded();
    std::lock_guard lock(mutex_);
    return tracks_.at(index);
}

void ScrobbleCache::Add(Track track)
{
    EnsureLoaded();
    {
        std::lock_guard lock(mutex_);
        tracks_.push_back(std::move(track));
    }
    Save();
}

void ScrobbleCache::Evict(size_t count)
{
    std::lock_guard lock(mutex_);
    count = std::min(count, tracks_.size());
    tracks_.erase(tracks_.begin(), tracks_.begin() + count);
}

void ScrobbleCache::Save()
{
    std::lock_guard lock(mutex_);

    NSMutableArray* array = [NSMutableArray arrayWithCapacity:tracks_.size()];
    for (auto const& track : tracks_) {
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        dict[@"timestamp"] = @(track.Timestamp.time_since_epoch().count());
        dict[@"artist"] = [NSString stringWithUTF8String:track.Artist.c_str()];
        dict[@"title"] = [NSString stringWithUTF8String:track.Title.c_str()];
        dict[@"albumArtist"] = [NSString stringWithUTF8String:track.AlbumArtist.c_str()];
        dict[@"album"] = [NSString stringWithUTF8String:track.Album.c_str()];
        dict[@"trackNumber"] = [NSString stringWithUTF8String:track.TrackNumber.c_str()];
        dict[@"mbid"] = [NSString stringWithUTF8String:track.MusicBrainzId.c_str()];
        dict[@"duration"] = @(track.Duration.count());
        dict[@"isDynamic"] = @(track.IsDynamic);
        [array addObject:dict];
    }

    @try {
        NSError* error = nil;
        NSData* data = [NSJSONSerialization dataWithJSONObject:array options:0 error:&error];
        if (!error) {
            NSString* path = [NSString stringWithUTF8String:GetFilePath().c_str()];
            [data writeToFile:path atomically:YES];
        }
    } @catch (...) {}
}

} // namespace foo_scrobble
