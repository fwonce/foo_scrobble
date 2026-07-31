// Last.fm API credentials
//
// DO NOT commit real API keys to git. Instead, create Keys.local.h
// (see Keys.local.h.template) with your own key and secret.
// Keys.local.h is listed in .gitignore and loaded via -include in the Makefile.
//
// If Keys.local.h does not exist, empty placeholders are used.

#include "Keys.h"

#ifdef FOO_SCROBBLE_HAVE_LOCAL_KEYS
#include "Keys.local.h"
#else
namespace lastfm {
char const* const ApiKey = "";
char const* const Secret = "";
}
#endif
