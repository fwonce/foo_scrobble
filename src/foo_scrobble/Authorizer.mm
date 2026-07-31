#include "Authorizer.h"

#include <helpers-mac/fb2k-platform.h>

namespace foo_scrobble
{

static Authorizer::State FromSessionKey(pfc::string_base const& sessionKey)
{
    if (sessionKey.get_length() > 0)
        return Authorizer::State::Authorized;
    return Authorizer::State::Unauthorized;
}

Authorizer::Authorizer(pfc::string_base const& sessionKey)
    : state_(FromSessionKey(sessionKey))
    , sessionKey_(sessionKey)
    , webService_(lastfm::ApiKey, lastfm::Secret)
{}

void Authorizer::ClearAuth()
{
    sessionKey_ = "";
    state_ = State::Unauthorized;
}

void Authorizer::RequestAuth(StateChangeHandler onComplete)
{
    if (state_ == State::RequestingAuth)
        return;

    state_ = State::RequestingAuth;
    console::info("foo_scrobble: Requesting auth token");

    webService_.GetAuthToken([this, onComplete](WebResult<std::string> result) {
        if (!result) {
            FB2K_console_formatter()
                << "foo_scrobble: Failed to get auth token";
            state_ = FromSessionKey(sessionKey_);
            if (onComplete) onComplete(state_);
            return;
        }

        authToken_ = result.value();
        FB2K_console_formatter()
            << "foo_scrobble: Received auth token: " << authToken_.c_str();

        // Open browser for authorization
        std::string url = "http://www.last.fm/api/auth?api_key=";
        url += lastfm::ApiKey;
        url += "&token=";
        url += authToken_;
        fb2k::openWebBrowser(url.c_str());

        state_ = State::WaitingForApproval;
        if (onComplete) onComplete(state_);
    });
}

void Authorizer::CompleteAuth(StateChangeHandler onComplete)
{
    if (state_ == State::CompletingAuth)
        return;

    state_ = State::CompletingAuth;
    console::info("foo_scrobble: Requesting session key");

    webService_.GetSessionKey(authToken_.c_str(),
        [this, onComplete](WebResult<std::string> result) {
            if (!result) {
                FB2K_console_formatter()
                    << "foo_scrobble: Failed to get session key";
                state_ = FromSessionKey(sessionKey_);
                if (onComplete) onComplete(state_);
                return;
            }

            std::string& sessionKey = result.value();
            FB2K_console_formatter()
                << "foo_scrobble: New session key: " << sessionKey.c_str();

            sessionKey_ = sessionKey.c_str();
            authToken_.clear();
            state_ = FromSessionKey(sessionKey_);
            if (onComplete) onComplete(state_);
        });
}

} // namespace foo_scrobble
