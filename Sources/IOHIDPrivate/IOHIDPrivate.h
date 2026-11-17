// Private IOKit HID functions that the temperature sensors need and the SDK headers leave out.
// Undocumented: a macOS update can change them, so callers treat every failure as "no sensors".
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>

// Inside this region Swift releases what Create… and Copy… return (+1) by itself, provided the
// type is CF_BRIDGED_TYPE. Declared as plain pointers, every event would leak on every refresh.
CF_IMPLICIT_BRIDGING_ENABLED
CF_ASSUME_NONNULL_BEGIN

typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;

IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

CF_ASSUME_NONNULL_END
CF_IMPLICIT_BRIDGING_DISABLED
