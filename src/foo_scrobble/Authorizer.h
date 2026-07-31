#pragma once
#include "WebService.h"

#include <SDK/foobar2000.h>
#include <functional>
#include <string>

namespace foo_scrobble
{

class Authorizer
{
public:
    enum class State
    {
        Unauthorized = 0,
        RequestingAuth,
        WaitingForApproval,
        CompletingAuth,
        Authorized,
    };

    using StateChangeHandler = std::function<void(State)>;

    explicit Authorizer(pfc::string_base const& sessionKey);

    State GetState() const { return state_; }
    pfc::string8_fast GetSessionKey() const { return sessionKey_; }

    void ClearAuth();
    void RequestAuth(StateChangeHandler onComplete);
    void CompleteAuth(StateChangeHandler onComplete);

private:
    State state_ = State::Unauthorized;
    pfc::string8_fast sessionKey_;
    std::string authToken_;
    WebService webService_;
};

} // namespace foo_scrobble
