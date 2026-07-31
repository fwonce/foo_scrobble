#include <SDK/foobar2000.h>

// Component version declaration
DECLARE_COMPONENT_VERSION(
    "Scrobble",
    "1.0.0",
    "foo_scrobble - Last.fm scrobbling for foobar2000 macOS\n"
    "\n"
    "Scrobbles played tracks to Last.fm / Audioscrobbler.\n"
    "Based on foo_scrobble for Windows by gix.\n"
)

// Validate component filename (Mac uses .component bundle)
VALIDATE_COMPONENT_FILENAME("foo_scrobble.component")
