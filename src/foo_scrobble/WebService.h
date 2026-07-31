#pragma once
#include "Track.h"

#include <SDK/foobar2000.h>

#include <functional>
#include <map>
#include <string>
#include <string_view>
#include <system_error>

namespace lastfm
{

extern char const* const ApiKey;
extern char const* const Secret;

enum class Status
{
    Success = 0,
    InvalidService = 2,
    InvalidMethod = 3,
    AuthenticationFailed = 4,
    InvalidFormat = 5,
    InvalidParameters = 6,
    InvalidResourceSpecified = 7,
    OperationFailed = 8,
    InvalidSessionKey = 9,
    InvalidAPIKey = 10,
    ServiceOffline = 11,
    InvalidMethodSignature = 13,
    TokenNotAuthorized = 14,
    ServiceTemporarilyUnavailable = 16,
    SuspendedAPIKey = 26,
    RateLimitExceeded = 29,
    InvalidResponse = -1,
    InternalError = -2,
    ConnectionError = -3,
    EncodingError = -4,
};

} // namespace lastfm

namespace std
{
template<>
struct is_error_code_enum<lastfm::Status> : true_type
{};

template<>
struct is_error_condition_enum<lastfm::Status> : true_type
{};
} // namespace std

namespace lastfm
{

class ErrorCategory : public std::error_category
{
public:
    char const* name() const noexcept override { return "last.fm api"; }

    std::string message(int ev) const override;
};

inline std::error_category const& webservice_category()
{
    static ErrorCategory instance;
    return instance;
}

inline std::error_code make_error_code(Status st)
{
    return {static_cast<int>(st), webservice_category()};
}

} // namespace lastfm

namespace foo_scrobble
{

template<typename T>
class WebResult
{
public:
    static WebResult Success(T value = T{}) { return WebResult(std::move(value)); }
    static WebResult Error(lastfm::Status status) { return WebResult(status); }
    static WebResult Exception(std::exception_ptr ex) { return WebResult(std::move(ex)); }

    bool has_value() const { return !error_ && !exception_; }
    bool has_error() const { return error_.has_value(); }
    bool has_exception() const { return exception_ != nullptr; }

    T& value() { return value_; }
    T const& value() const { return value_; }
    std::error_code error() const { return *error_; }
    std::exception_ptr exception() const { return exception_; }

    operator bool() const { return has_value(); }

private:
    WebResult(T value) : value_(std::move(value)) {}
    WebResult(lastfm::Status status) : error_(lastfm::make_error_code(status)) {}
    WebResult(std::exception_ptr ex) : exception_(std::move(ex)) {}

    T value_{};
    std::optional<std::error_code> error_;
    std::exception_ptr exception_;
};

//! Specialization for void results (scrobble/nowplaying)
class WebVoidResult
{
public:
    static WebVoidResult Success() { return WebVoidResult(); }
    static WebVoidResult Error(lastfm::Status status) { return WebVoidResult(status); }
    static WebVoidResult Exception(std::exception_ptr ex) { return WebVoidResult(std::move(ex)); }

    bool has_value() const { return !error_ && !exception_; }
    bool has_error() const { return error_.has_value(); }
    bool has_exception() const { return exception_ != nullptr; }

    std::error_code error() const { return *error_; }
    std::exception_ptr exception() const { return exception_; }

    operator bool() const { return has_value(); }

private:
    WebVoidResult() = default;
    WebVoidResult(lastfm::Status status) : error_(lastfm::make_error_code(status)) {}
    WebVoidResult(std::exception_ptr ex) : exception_(std::move(ex)) {}

    std::optional<std::error_code> error_;
    std::exception_ptr exception_;
};

class Track;

class WebService
{
public:
    using CompletionHandler = std::function<void(WebResult<std::string>)>;
    using VoidCompletionHandler = std::function<void(WebVoidResult)>;

    explicit WebService(char const* apiKey, char const* secret);
    ~WebService();

    void SetSessionKey(std::string_view newSessionKey)
    {
        sessionKey_ = std::string(newSessionKey);
    }

    void GetAuthToken(CompletionHandler completion);
    void GetSessionKey(std::string_view authToken, CompletionHandler completion);
    void SendNowPlaying(Track const& track, VoidCompletionHandler completion);
    void Scrobble(Track const& track, VoidCompletionHandler completion);

    class MapIndex
    {
        static constexpr size_t MaxSize = 16;

    public:
        MapIndex() = default;

        MapIndex(std::string_view name)
            : length_(static_cast<uint8_t>(std::min(MaxSize, name.length())))
        {
            std::memcpy(name_, name.data(), length_);
        }

        MapIndex(std::string_view name, uint8_t index)
            : length_(static_cast<uint8_t>(std::min(MaxSize - 4, name.length())))
        {
            std::memcpy(name_, name.data(), length_);
            AddIndex(index);
        }

        char const* data() const noexcept { return name_; }
        size_t length() const noexcept { return length_; }
        std::string_view string() const noexcept { return {name_, length_}; }

        bool operator<(MapIndex const& other) const noexcept;

    private:
        void AddIndex(uint8_t index)
        {
            name_[length_++] = '[';
            if (index >= 10)
                name_[length_++] = ('0' + (index / 10));
            name_[length_++] = ('0' + (index % 10));
            name_[length_++] = ']';
        }

        char name_[MaxSize];
        uint8_t length_ = 0;
    };

    using ParamsMap = std::map<MapIndex, std::string>;

    class ScrobbleRequest
    {
    public:
        ScrobbleRequest(ScrobbleRequest&&) = default;
        ScrobbleRequest& operator=(ScrobbleRequest&&) = default;

        uint8_t TrackCount() const { return trackCount_; }
        bool AddTrack(Track const& track);

    private:
        explicit ScrobbleRequest(ParamsMap params)
            : params_(std::move(params))
        {}

        ParamsMap TakeParams() { return std::move(params_); }

        ParamsMap params_;
        uint8_t trackCount_ = 0;

        friend class WebService;
    };

    ScrobbleRequest CreateScrobbleRequest();
    void Scrobble(ScrobbleRequest request, VoidCompletionHandler completion);

private:
    ParamsMap NewParams(std::string_view method) const;
    ParamsMap NewAuthedParams(std::string_view method) const;
    void SignRequestParams(ParamsMap& params);
    void PostRequest(ParamsMap const& params, CompletionHandler completion);

    void* session_; // NSURLSession*
    std::string const apiKey_;
    std::string const secret_;
    std::string sessionKey_;
};

} // namespace foo_scrobble
