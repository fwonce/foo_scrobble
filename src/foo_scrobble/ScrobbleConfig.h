#pragma once
#include <SDK/foobar2000.h>
#include <SDK/cfg_var.h>

namespace foo_scrobble
{

inline constexpr char const* DefaultArtistMapping = "[%artist%]";
inline constexpr char const* DefaultTitleMapping = "[%title%]";
inline constexpr char const* DefaultAlbumMapping = "[%album%]";
inline constexpr char const* DefaultAlbumArtistMapping = "[%album artist%]";
inline constexpr char const* DefaultTrackNumberMapping = "[%tracknumber%]";
inline constexpr char const* DefaultMBTrackIdMapping = "[%musicbrainz_trackid%]";

class ScrobbleConfig
{
public:
    ScrobbleConfig() = default;

    bool GetEnableScrobbling() { return enableScrobbling_.get(); }
    void SetEnableScrobbling(bool v) { enableScrobbling_.set(v); }

    bool GetEnableNowPlaying() { return enableNowPlaying_.get(); }
    void SetEnableNowPlaying(bool v) { enableNowPlaying_.set(v); }

    bool GetSubmitOnlyInLibrary() { return submitOnlyInLibrary_.get(); }
    void SetSubmitOnlyInLibrary(bool v) { submitOnlyInLibrary_.set(v); }

    bool GetSubmitDynamicSources() { return submitDynamicSources_.get(); }
    void SetSubmitDynamicSources(bool v) { submitDynamicSources_.set(v); }

    pfc::string8 GetArtistMapping() { return artistMapping_.get(); }
    void SetArtistMapping(const char* v) { artistMapping_.set(v); }

    pfc::string8 GetTitleMapping() { return titleMapping_.get(); }
    void SetTitleMapping(const char* v) { titleMapping_.set(v); }

    pfc::string8 GetAlbumMapping() { return albumMapping_.get(); }
    void SetAlbumMapping(const char* v) { albumMapping_.set(v); }

    pfc::string8 GetAlbumArtistMapping() { return albumArtistMapping_.get(); }
    void SetAlbumArtistMapping(const char* v) { albumArtistMapping_.set(v); }

    pfc::string8 GetTrackNumberMapping() { return trackNumberMapping_.get(); }
    void SetTrackNumberMapping(const char* v) { trackNumberMapping_.set(v); }

    pfc::string8 GetMBTrackIdMapping() { return mbTrackIdMapping_.get(); }
    void SetMBTrackIdMapping(const char* v) { mbTrackIdMapping_.set(v); }

    pfc::string8 GetSkipSubmissionFormat() { return skipSubmissionFormat_.get(); }
    void SetSkipSubmissionFormat(const char* v) { skipSubmissionFormat_.set(v); }

    pfc::string8 GetSessionKey() { return sessionKey_.get(); }
    void SetSessionKey(const char* v) { sessionKey_.set(v); }
    void ResetSessionKey() { sessionKey_.set(""); }

private:
    // {A1B2C3D4-0001-0001-0001-000000000001}
    static constexpr GUID guid_enableScrobbling =
        {0xA1B2C3D4, 0x0001, 0x0001, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01}};
    static constexpr GUID guid_enableNowPlaying =
        {0xA1B2C3D4, 0x0001, 0x0001, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02}};
    static constexpr GUID guid_submitOnlyInLibrary =
        {0xA1B2C3D4, 0x0001, 0x0001, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03}};
    static constexpr GUID guid_submitDynamicSources =
        {0xA1B2C3D4, 0x0001, 0x0001, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04}};

    // {A1B2C3D4-0001-0002-XXXX-XXXXXXXXXXXX}
    static constexpr GUID guid_artistMapping =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01}};
    static constexpr GUID guid_titleMapping =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02}};
    static constexpr GUID guid_albumMapping =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03}};
    static constexpr GUID guid_albumArtistMapping =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04}};
    static constexpr GUID guid_trackNumberMapping =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05}};
    static constexpr GUID guid_mbTrackIdMapping =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06}};
    static constexpr GUID guid_skipSubmissionFormat =
        {0xA1B2C3D4, 0x0001, 0x0002, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07}};

    // {A1B2C3D4-0001-0003-XXXX-XXXXXXXXXXXX}
    static constexpr GUID guid_sessionKey =
        {0xA1B2C3D4, 0x0001, 0x0003, {0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01}};

    cfg_var_modern::cfg_bool enableScrobbling_{guid_enableScrobbling, true};
    cfg_var_modern::cfg_bool enableNowPlaying_{guid_enableNowPlaying, true};
    cfg_var_modern::cfg_bool submitOnlyInLibrary_{guid_submitOnlyInLibrary, false};
    cfg_var_modern::cfg_bool submitDynamicSources_{guid_submitDynamicSources, true};

    cfg_var_modern::cfg_string artistMapping_{guid_artistMapping, DefaultArtistMapping};
    cfg_var_modern::cfg_string titleMapping_{guid_titleMapping, DefaultTitleMapping};
    cfg_var_modern::cfg_string albumMapping_{guid_albumMapping, DefaultAlbumMapping};
    cfg_var_modern::cfg_string albumArtistMapping_{guid_albumArtistMapping, DefaultAlbumArtistMapping};
    cfg_var_modern::cfg_string trackNumberMapping_{guid_trackNumberMapping, DefaultTrackNumberMapping};
    cfg_var_modern::cfg_string mbTrackIdMapping_{guid_mbTrackIdMapping, DefaultMBTrackIdMapping};
    cfg_var_modern::cfg_string skipSubmissionFormat_{guid_skipSubmissionFormat, ""};

    cfg_var_modern::cfg_string sessionKey_{guid_sessionKey, ""};
};

class NOVTABLE ScrobbleConfigNotify : public service_base
{
public:
    virtual void OnConfigChanged() = 0;

    static void NotifyChanged()
    {
        for (auto ptr : ScrobbleConfigNotify::enumerate())
            ptr->OnConfigChanged();
    }

    FB2K_MAKE_SERVICE_INTERFACE_ENTRYPOINT(ScrobbleConfigNotify)
};

extern ScrobbleConfig Config;

} // namespace foo_scrobble
