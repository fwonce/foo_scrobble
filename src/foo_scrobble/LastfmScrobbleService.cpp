#include "ScrobbleService.h"

#include "ScrobbleCache.h"
#include "ScrobbleConfig.h"
#include "TokenBucketRateLimiter.h"
#include "Track.h"
#include "WebService.h"

#include <dispatch/dispatch.h>
#include <string_view>

using namespace std::chrono;
using namespace std::string_view_literals;

namespace foo_scrobble
{
namespace
{

class LastfmScrobbleService : public ScrobbleService
{
public:
    LastfmScrobbleService()
        : webService_(lastfm::ApiKey, lastfm::Secret)
        , rateLimiter_(5.0, ComputeBurstCapacity(5.0))
    {}

    void ScrobbleAsync(Track track) override;
    void SendNowPlayingAsync(Track const& track) override;
    void Shutdown() override;

private:
    enum class State
    {
        UnauthenticatedIdle,
        AuthenticatedIdle,
        AwaitingResponse,
        Sleeping,
        Suspended,
        ShuttingDown,
        ShutDown,
    };

    void OnScrobbleResponse(WebVoidResult result);
    void OnNowPlayingResponse(WebVoidResult result);
    void OnWakeUp();

    void LogResponse(std::string_view task, WebVoidResult const& result);
    void HandleResponseStatus(lastfm::Status status);

    void ProcessLocked();
    void PauseProcessing(duration<int, std::milli> delay);
    void SetSessionKey(pfc::string_base const& newSessionKey);
    void SetSessionKeyLocked(pfc::string_base const& newSessionKey);
    void ClearSessionKeyLocked();

    static constexpr double ComputeBurstCapacity(double tokensPerSecond)
    {
        return (5 * 60) * tokensPerSecond / 2.0;
    }

    static constexpr size_t MaxScrobblesPerRequestLimit = 50;

    using ExclusiveLock = std::scoped_lock<std::mutex>;
    std::mutex mutex_;
    std::condition_variable cv_;

    WebService webService_;
    TokenBucketRateLimiter rateLimiter_;

    State state_ = State::UnauthenticatedIdle;
    ScrobbleCache& scrobbleCache_ = ScrobbleCache::Get();
    size_t pendingSubmissionSize_ = 0;
    Track pendingNowPlaying_;
    size_t maxScrobblesPerRequest_ = MaxScrobblesPerRequestLimit;
};

void LastfmScrobbleService::ScrobbleAsync(Track track)
{
    ExclusiveLock lock(mutex_);
    scrobbleCache_.Add(std::move(track));

    // Lazy session key loading
    if (state_ == State::UnauthenticatedIdle) {
        auto key = Config.GetSessionKey();
        if (key.get_length() > 0) {
            SetSessionKeyLocked(key);
        }
    }

    switch (state_) {
    case State::AuthenticatedIdle:
        break;
    case State::UnauthenticatedIdle:
        FB2K_console_formatter() << "foo_scrobble: Queuing scrobble (Unauthenticated)";
        return;
    case State::Suspended:
        FB2K_console_formatter() << "foo_scrobble: Queuing scrobble (Invalid API key)";
        return;
    case State::Sleeping:
        FB2K_console_formatter() << "foo_scrobble: Queuing scrobble (Sleeping)";
        return;
    case State::AwaitingResponse:
    case State::ShuttingDown:
    case State::ShutDown:
        return;
    }

    ProcessLocked();
}

void LastfmScrobbleService::SendNowPlayingAsync(Track const& track)
{
    ExclusiveLock lock(mutex_);
    pendingNowPlaying_ = track;

    // Lazy session key loading
    if (state_ == State::UnauthenticatedIdle) {
        auto key = Config.GetSessionKey();
        if (key.get_length() > 0) {
            SetSessionKeyLocked(key);
        }
    }

    switch (state_) {
    case State::UnauthenticatedIdle:
    case State::Sleeping:
    case State::Suspended:
    case State::ShuttingDown:
    case State::ShutDown:
    case State::AwaitingResponse:
        return;
    case State::AuthenticatedIdle:
        break;
    }

    ProcessLocked();
}

void LastfmScrobbleService::SetSessionKey(pfc::string_base const& newSessionKey)
{
    ExclusiveLock lock(mutex_);
    SetSessionKeyLocked(newSessionKey);
}

void LastfmScrobbleService::SetSessionKeyLocked(pfc::string_base const& newSessionKey)
{
    webService_.SetSessionKey({newSessionKey.get_ptr(), newSessionKey.get_length()});

    if (newSessionKey.is_empty()) {
        switch (state_) {
        case State::ShuttingDown:
        case State::ShutDown:
        case State::UnauthenticatedIdle:
        case State::Suspended:
            break;
        case State::AwaitingResponse:
        case State::Sleeping:
            state_ = State::UnauthenticatedIdle;
            break;
        case State::AuthenticatedIdle:
            state_ = State::UnauthenticatedIdle;
            break;
        }
    } else {
        if (state_ == State::UnauthenticatedIdle) {
            state_ = State::AuthenticatedIdle;
            ProcessLocked();
        }
    }
}

void LastfmScrobbleService::ClearSessionKeyLocked()
{
    SetSessionKeyLocked(pfc::string8());
    fb2k::inMainThread([]() { Config.ResetSessionKey(); });
}

void LastfmScrobbleService::Shutdown()
{
    std::unique_lock<std::mutex> lock(mutex_);

    switch (state_) {
    case State::ShuttingDown:
        return;
    case State::UnauthenticatedIdle:
    case State::AuthenticatedIdle:
    case State::Suspended:
    case State::Sleeping:
    case State::ShutDown:
        state_ = State::ShutDown;
        return;
    case State::AwaitingResponse:
        state_ = State::ShuttingDown;
        break;
    }

    cv_.wait_for(lock, milliseconds(500),
                 [this]() { return state_ == State::ShutDown; });
    if (state_ != State::ShutDown)
        state_ = State::ShutDown;
}

void LastfmScrobbleService::OnWakeUp()
{
    ExclusiveLock lock(mutex_);

    switch (state_) {
    case State::ShuttingDown:
    case State::ShutDown:
        return;
    case State::Sleeping:
        state_ = State::AuthenticatedIdle;
        ProcessLocked();
        break;
    default:
        break;
    }
}

void LastfmScrobbleService::ProcessLocked()
{
    if (state_ != State::AuthenticatedIdle) {
        return;
    }

    if (!pendingNowPlaying_.IsValid() && scrobbleCache_.IsEmpty()) {
        return;
    }

    auto const delay = duration_cast<duration<int, std::milli>>(rateLimiter_.Acquire());
    if (delay.count() != 0) {
        PauseProcessing(delay);
        return;
    }

    if (pendingNowPlaying_.IsValid()) {
        state_ = State::AwaitingResponse;
        Track track = pendingNowPlaying_;
        webService_.SendNowPlaying(track, [this](WebVoidResult result) {
            OnNowPlayingResponse(result);
        });
        return;
    }

    if (scrobbleCache_.Count() == 1) {
        pendingSubmissionSize_ = 1;
        FB2K_console_formatter() << "foo_scrobble: Submitting track";

        state_ = State::AwaitingResponse;
        Track track = scrobbleCache_[0];
        webService_.Scrobble(track, [this](WebVoidResult result) {
            OnScrobbleResponse(result);
        });
    } else if (scrobbleCache_.Count() > 1) {
        size_t const batchSize = std::min(scrobbleCache_.Count(),
                                          maxScrobblesPerRequest_);
        pendingSubmissionSize_ = batchSize;
        auto request = webService_.CreateScrobbleRequest();
        for (size_t i = 0; i < batchSize; ++i)
            request.AddTrack(scrobbleCache_[i]);

        FB2K_console_formatter() << "foo_scrobble: Submitting " << batchSize << " of "
                                 << scrobbleCache_.Count() << " cached tracks";

        state_ = State::AwaitingResponse;
        webService_.Scrobble(std::move(request), [this](WebVoidResult result) {
            OnScrobbleResponse(result);
        });
    }
}

void LastfmScrobbleService::PauseProcessing(duration<int, std::milli> delay)
{
    state_ = State::Sleeping;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, delay.count() * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            this->OnWakeUp();
        });
}

lastfm::Status AsStatus(WebVoidResult const& result)
{
    if (result)
        return lastfm::Status::Success;
    if (result.has_error())
        return static_cast<lastfm::Status>(result.error().value());
    return lastfm::Status::InternalError;
}

void LastfmScrobbleService::OnScrobbleResponse(WebVoidResult result)
{
    {
        ExclusiveLock lock(mutex_);

        LogResponse("Scrobbling"sv, result);
        auto const status = AsStatus(result);

        switch (status) {
        case lastfm::Status::Success:
            scrobbleCache_.Evict(pendingSubmissionSize_);
            pendingSubmissionSize_ = 0;
            maxScrobblesPerRequest_ = MaxScrobblesPerRequestLimit;
            break;
        case lastfm::Status::InvalidParameters:
        case lastfm::Status::EncodingError:
            if (pendingSubmissionSize_ == 1) {
                scrobbleCache_.Evict(pendingSubmissionSize_);
                pendingSubmissionSize_ = 0;
                maxScrobblesPerRequest_ = MaxScrobblesPerRequestLimit;
            } else {
                maxScrobblesPerRequest_ = 1;
            }
            break;
        default:
            break;
        }

        HandleResponseStatus(status);
    }
    cv_.notify_all();
}

void LastfmScrobbleService::OnNowPlayingResponse(WebVoidResult result)
{
    {
        ExclusiveLock lock(mutex_);

        LogResponse("NowPlaying notification"sv, result);
        auto const status = AsStatus(result);

        switch (status) {
        case lastfm::Status::InvalidSessionKey:
        case lastfm::Status::ServiceOffline:
        case lastfm::Status::ServiceTemporarilyUnavailable:
        case lastfm::Status::ConnectionError:
            break;
        case lastfm::Status::Success:
        default:
            pendingNowPlaying_ = {};
            break;
        }

        HandleResponseStatus(status);
    }
    cv_.notify_all();
}

void LastfmScrobbleService::HandleResponseStatus(lastfm::Status status)
{
    if (state_ == State::AwaitingResponse) {
        switch (status) {
        case lastfm::Status::Success:
            state_ = State::AuthenticatedIdle;
            ProcessLocked();
            break;
        case lastfm::Status::AuthenticationFailed:
            PauseProcessing(minutes(1));
            break;
        case lastfm::Status::InvalidSessionKey:
            state_ = State::UnauthenticatedIdle;
            ClearSessionKeyLocked();
            break;
        case lastfm::Status::InvalidAPIKey:
        case lastfm::Status::SuspendedAPIKey:
            state_ = State::Suspended;
            break;
        case lastfm::Status::ServiceOffline:
        case lastfm::Status::ServiceTemporarilyUnavailable:
            PauseProcessing(minutes(2));
            break;
        case lastfm::Status::RateLimitExceeded:
            PauseProcessing(minutes(2));
            break;
        case lastfm::Status::InvalidService:
        case lastfm::Status::InvalidResponse:
        case lastfm::Status::InternalError:
            PauseProcessing(minutes(1));
            break;
        case lastfm::Status::ConnectionError:
            PauseProcessing(seconds(30));
            break;
        default:
            PauseProcessing(seconds(20));
            break;
        }
    } else {
        state_ = State::ShutDown;
    }
}

void LastfmScrobbleService::LogResponse(std::string_view task,
                                         WebVoidResult const& result)
{
    if (result.has_value())
        return;

    if (result.has_exception()) {
        FB2K_console_formatter() << "foo_scrobble: " << std::string(task).c_str() << " failed (exception)";
        return;
    }

    auto const status = static_cast<lastfm::Status>(result.error().value());
    if (status == lastfm::Status::Success)
        return;

    FB2K_console_formatter() << "foo_scrobble: " << std::string(task).c_str() << " failed (error "
                             << static_cast<int>(status) << ")";
}

} // namespace

static service_factory_single_t<LastfmScrobbleService>
    g_LastfmScrobblerService;

// Separate init_stage_callback to trigger session key loading on startup
class ScrobbleInitHandler : public init_stage_callback {
public:
    void on_init_stage(t_uint32 stage) override {
        if (stage == init_stages::after_ui_init) {
            // The session key will be read from Config when the service first needs it
            console::info("foo_scrobble: Initialized, session key will be loaded on first use");
        }
    }
};

static service_factory_single_t<ScrobbleInitHandler> g_ScrobbleInitHandler;

} // namespace foo_scrobble
