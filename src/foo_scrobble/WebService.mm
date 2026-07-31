#include "WebService.h"
#include "Track.h"

#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>

#include <string_view>

using namespace std::string_literals;
using namespace std::string_view_literals;

namespace foo_scrobble
{

namespace
{

std::string Md5Hex(std::string_view data)
{
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.data(), static_cast<CC_LONG>(data.size()), digest);

    static char const* hexChars = "0123456789abcdef";
    std::string result;
    result.reserve(32);
    for (unsigned char c : digest) {
        result += hexChars[(c >> 4) & 0xF];
        result += hexChars[c & 0xF];
    }
    return result;
}

class FormDataBuilder
{
public:
    FormDataBuilder() = default;
    FormDataBuilder(size_t capacity) { encoded_.reserve(capacity); }

    void Append(std::string_view name, std::string_view value)
    {
        if (!encoded_.empty())
            encoded_.push_back('&');

        AppendEncoded(name);
        encoded_.push_back('=');
        AppendEncoded(value);
    }

    std::string ReleaseString() { return std::move(encoded_); }

private:
    static bool IsRawByte(char c)
    {
        return c == 0x2A || c == 0x2D || c == 0x2E ||
               (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) ||
               c == 0x5F || (c >= 0x61 && c <= 0x7A);
    }

    void AppendEncoded(std::string_view str)
    {
        static char const* upperHex = "0123456789ABCDEF";
        for (char const c : str) {
            if (c == 0x20) {
                encoded_.push_back('+');
            } else if (IsRawByte(c)) {
                encoded_.push_back(c);
            } else {
                encoded_.push_back('%');
                encoded_.push_back(upperHex[(c >> 4) & 0xF]);
                encoded_.push_back(upperHex[c & 0xF]);
            }
        }
    }

    std::string encoded_;
};

int Compare(char const* str1, size_t length1, char const* str2, size_t length2) noexcept
{
    int const cmp = std::memcmp(str1, str2, std::min(length1, length2));
    if (cmp != 0) return cmp;
    if (length1 < length2) return -1;
    if (length1 > length2) return 1;
    return 0;
}

void FillParamsFromTrack(WebService::ParamsMap& params, Track const& track, bool simple = false)
{
    if (!simple)
        params["timestamp"sv] = std::to_string(track.Timestamp.time_since_epoch().count());

    params["artist"sv] = track.Artist;
    params["track"sv] = track.Title;

    if (track.Duration > std::chrono::seconds::zero())
        params["duration"sv] = std::to_string(
            static_cast<int>(std::round(track.Duration.count())));

    if (!track.Album.is_empty()) {
        params["album"sv] = track.Album;
        if (!track.TrackNumber.is_empty())
            params["trackNumber"sv] = track.TrackNumber;
        if (!track.AlbumArtist.is_empty())
            params["albumArtist"sv] = track.AlbumArtist;
    }

    if (!track.MusicBrainzId.is_empty())
        params["mbid"sv] = track.MusicBrainzId;

    if (track.IsDynamic)
        params["chosenByUser"sv] = "0";
}

void FillParamsFromTrack(WebService::ParamsMap& params, Track const& track, uint8_t index)
{
    params[{"timestamp"sv, index}] = std::to_string(
        track.Timestamp.time_since_epoch().count());
    params[{"artist"sv, index}] = track.Artist;
    params[{"track"sv, index}] = track.Title;

    if (track.Duration > std::chrono::seconds::zero())
        params[{"duration"sv, index}] = std::to_string(
            static_cast<int>(std::round(track.Duration.count())));

    if (!track.Album.is_empty()) {
        params[{"album"sv, index}] = track.Album;
        if (!track.TrackNumber.is_empty())
            params[{"trackNumber"sv, index}] = track.TrackNumber;
        if (!track.AlbumArtist.is_empty())
            params[{"albumArtist"sv, index}] = track.AlbumArtist;
    }

    if (!track.MusicBrainzId.is_empty())
        params[{"mbid"sv, index}] = track.MusicBrainzId;

    if (track.IsDynamic)
        params[{"chosenByUser"sv, index}] = "0";
}

lastfm::Status ExtractError(NSData* responseData)
{
    @try {
        NSError* jsonError = nil;
        NSDictionary* msg = [NSJSONSerialization JSONObjectWithData:responseData
                                                           options:0
                                                             error:&jsonError];
        if (jsonError || ![msg isKindOfClass:[NSDictionary class]])
            return lastfm::Status::InvalidResponse;

        NSNumber* errorCode = msg[@"error"];
        if (errorCode)
            return static_cast<lastfm::Status>(errorCode.intValue);
    } @catch (...) {}

    return lastfm::Status::InvalidResponse;
}

NSString* const kServiceBaseUrl = @"https://ws.audioscrobbler.com/2.0/";

} // anonymous namespace

WebService::WebService(char const* apiKey, char const* secret)
    : apiKey_(apiKey)
    , secret_(secret)
{
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
    session_ = (__bridge_retained void*)[NSURLSession sessionWithConfiguration:config];
}

WebService::~WebService()
{
    NSURLSession* session = (__bridge_transfer NSURLSession*)session_;
    [session invalidateAndCancel];
}

WebService::ParamsMap WebService::NewParams(std::string_view method) const
{
    ParamsMap params;
    params.insert({"api_key"sv, apiKey_});
    params.insert({"format"sv, "json"});
    params.insert({"method"sv, std::string(method)});
    return params;
}

WebService::ParamsMap WebService::NewAuthedParams(std::string_view method) const
{
    auto params = NewParams(method);
    params.insert({"sk"sv, sessionKey_});
    return params;
}

void WebService::SignRequestParams(ParamsMap& params)
{
    std::string concatenated;
    for (auto const& param : params) {
        if (param.first.string() == "format"sv || param.first.string() == "callback"sv)
            continue;
        concatenated.append(param.first.data(), param.first.length());
        concatenated.append(param.second.data(), param.second.length());
    }
    concatenated.append(secret_.data(), secret_.size());
    params["api_sig"sv] = Md5Hex(concatenated);
}

void WebService::PostRequest(ParamsMap const& params, CompletionHandler completion)
{
    FormDataBuilder formData;
    for (auto const& param : params)
        formData.Append(param.first.string(), param.second);

    std::string body = formData.ReleaseString();

    NSURL* url = [NSURL URLWithString:kServiceBaseUrl];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSData dataWithBytes:body.data() length:body.size()];

    NSURLSession* session = (__bridge NSURLSession*)session_;
    NSURLSessionDataTask* task = [session
        dataTaskWithRequest:request
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              if (error) {
                  completion(WebResult<std::string>::Exception(
                      std::make_exception_ptr(
                          std::runtime_error([[error localizedDescription] UTF8String]))));
                  return;
              }

              NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
              if (httpResponse.statusCode != 200) {
                  lastfm::Status status = ExtractError(data);
                  completion(WebResult<std::string>::Error(status));
                  return;
              }

              @try {
                  NSError* jsonError = nil;
                  NSDictionary* msg = [NSJSONSerialization JSONObjectWithData:data
                                                                     options:0
                                                                       error:&jsonError];
                  if (jsonError || ![msg isKindOfClass:[NSDictionary class]]) {
                      completion(WebResult<std::string>::Error(lastfm::Status::InvalidResponse));
                      return;
                  }

                  // Check for auth.getToken response
                  NSString* token = msg[@"token"];
                  if (token) {
                      completion(WebResult<std::string>::Success([token UTF8String]));
                      return;
                  }

                  // Check for auth.getSession response
                  NSDictionary* sessionDict = msg[@"session"];
                  if (sessionDict && [sessionDict isKindOfClass:[NSDictionary class]]) {
                      NSString* key = sessionDict[@"key"];
                      if (key) {
                          completion(WebResult<std::string>::Success([key UTF8String]));
                          return;
                      }
                  }

                  // For scrobble/nowplaying - just success
                  completion(WebResult<std::string>::Success(""));
              } @catch (NSException* exception) {
                  completion(WebResult<std::string>::Exception(
                      std::make_exception_ptr(
                          std::runtime_error([[exception reason] UTF8String]))));
              }
          }];
    [task resume];
}

void WebService::GetAuthToken(CompletionHandler completion)
{
    auto params = NewParams("auth.getToken");
    SignRequestParams(params);
    PostRequest(params, completion);
}

void WebService::GetSessionKey(std::string_view authToken, CompletionHandler completion)
{
    auto params = NewParams("auth.getSession");
    params["token"sv] = authToken;
    SignRequestParams(params);
    PostRequest(params, completion);
}

void WebService::SendNowPlaying(Track const& track, VoidCompletionHandler completion)
{
    auto params = NewAuthedParams("track.updateNowPlaying");
    FillParamsFromTrack(params, track, true);
    SignRequestParams(params);

    PostRequest(params, [completion](WebResult<std::string> result) {
        if (result.has_value())
            completion(WebVoidResult::Success());
        else if (result.has_error())
            completion(WebVoidResult::Error(static_cast<lastfm::Status>(result.error().value())));
        else
            completion(WebVoidResult::Exception(result.exception()));
    });
}

void WebService::Scrobble(Track const& track, VoidCompletionHandler completion)
{
    auto params = NewAuthedParams("track.scrobble");
    FillParamsFromTrack(params, track);
    SignRequestParams(params);

    PostRequest(params, [completion](WebResult<std::string> result) {
        if (result.has_value())
            completion(WebVoidResult::Success());
        else if (result.has_error())
            completion(WebVoidResult::Error(static_cast<lastfm::Status>(result.error().value())));
        else
            completion(WebVoidResult::Exception(result.exception()));
    });
}

bool WebService::MapIndex::operator<(MapIndex const& other) const noexcept
{
    return Compare(name_, length_, other.name_, other.length_) < 0;
}

WebService::ScrobbleRequest WebService::CreateScrobbleRequest()
{
    return ScrobbleRequest(NewAuthedParams("track.scrobble"));
}

bool WebService::ScrobbleRequest::AddTrack(Track const& track)
{
    FillParamsFromTrack(params_, track, trackCount_);
    ++trackCount_;
    return true;
}

void WebService::Scrobble(ScrobbleRequest request, VoidCompletionHandler completion)
{
    auto params = request.TakeParams();
    SignRequestParams(params);

    PostRequest(params, [completion](WebResult<std::string> result) {
        if (result.has_value())
            completion(WebVoidResult::Success());
        else if (result.has_error())
            completion(WebVoidResult::Error(static_cast<lastfm::Status>(result.error().value())));
        else
            completion(WebVoidResult::Exception(result.exception()));
    });
}

} // namespace foo_scrobble

// lastfm::ErrorCategory implementation
namespace lastfm
{

std::string ErrorCategory::message(int ev) const
{
    switch (static_cast<Status>(ev)) {
    case Status::Success: return "Success";
    case Status::InvalidService: return "The service does not exist.";
    case Status::InvalidMethod: return "No method with that name in this package.";
    case Status::AuthenticationFailed: return "No permissions to access the service.";
    case Status::InvalidFormat: return "The service does not exist in that format.";
    case Status::InvalidParameters: return "Request is missing a required parameter.";
    case Status::InvalidResourceSpecified: return "Invalid resource specified.";
    case Status::OperationFailed: return "Something else went wrong.";
    case Status::InvalidSessionKey: return "Please re-authenticate.";
    case Status::InvalidAPIKey: return "You must be granted a valid key by last.fm.";
    case Status::ServiceOffline: return "The service is temporarily offline.";
    case Status::InvalidMethodSignature: return "Invalid method signature.";
    case Status::ServiceTemporarilyUnavailable: return "Service temporarily unavailable.";
    case Status::SuspendedAPIKey: return "API key suspended.";
    case Status::RateLimitExceeded: return "Rate limit exceeded.";
    case Status::TokenNotAuthorized: return "Token not authorized.";
    case Status::InvalidResponse: return "Invalid response.";
    case Status::InternalError: return "Internal error.";
    case Status::ConnectionError: return "Connection error.";
    case Status::EncodingError: return "Encoding error.";
    default: return "Unknown error";
    }
}

} // namespace lastfm
