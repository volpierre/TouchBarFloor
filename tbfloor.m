// tbfloor.m
// Keeps the Touch Bar brightness at or above a chosen level (default: maximum),
// so it never drops into the low-brightness range where it flickers.
//
// Uses private Apple frameworks (DFRBrightness, CoreBrightness). The calls and
// argument types match the open-source TouchBarController project
// (github.com/skimmilk/TouchBarController), which was tested on a
// MacBookPro17,1 running macOS 27.0. Private APIs can change with any macOS update.
//
// Brightness writes are "transient" (Commit = NO): they do not save a new
// brightness preference. If this tool stops, macOS resumes its own control.
//
// Usage:
//   tbfloor status                 print current Touch Bar brightness info
//   tbfloor set <0.0-1.0>          set brightness once
//   tbfloor run [floor] [seconds]  keep brightness >= floor (default 1.0),
//                                  checking every [seconds] (default 0.5)

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <string.h>
#import <unistd.h>

static id dfrClient = nil;      // DFRBrightnessClient (Touch Bar display service)
static id coreClient = nil;     // BrightnessSystemClient (CoreBrightness)
static int displayID = -1;      // Touch Bar display ID, from DFRBrightnessClient

static NSString *timestamp(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [f stringFromDate:[NSDate date]];
}

// Reads a property from the Touch Bar's AppleARMBacklight driver node (read-only).
static id driverProperty(NSString *key) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"), &iterator) != KERN_SUCCESS)
        return nil;
    id value = nil;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) {
        io_object_t parent = IO_OBJECT_NULL;
        char parentName[128] = {0};
        if (IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS) {
            IORegistryEntryGetName(parent, parentName);
            IOObjectRelease(parent);
        }
        BOOL isTouchBar = strcmp(parentName, "backlight-dfr") == 0;
        if (isTouchBar) {
            value = CFBridgingRelease(IORegistryEntryCreateCFProperty(service, (__bridge CFStringRef)key,
                                                                      kCFAllocatorDefault, 0));
        }
        IOObjectRelease(service);
        if (isTouchBar) break;
    }
    IOObjectRelease(iterator);
    return value;
}

static id getCoreClient(void) {
    if (coreClient) return coreClient;
    if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY))
        return nil;
    Class cls = objc_getClass("BrightnessSystemClient");
    if (!cls) return nil;
    coreClient = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(new));
    return coreClient;
}

// Connects to the Touch Bar display service and gets its display ID.
static BOOL connectDFR(void) {
    dfrClient = nil;
    displayID = -1;
    if (!dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_LAZY))
        return NO;
    Class cls = objc_getClass("DFRBrightnessClient");
    if (!cls) return NO;

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    CFArrayRef services = system ? IOHIDEventSystemClientCopyServices(system) : NULL;
    if (!services) {
        if (system) CFRelease(system);
        return NO;
    }

    id client = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(new));
    BOOL ready = NO;
    if (client && ((BOOL (*)(id, SEL))objc_msgSend)(client, sel_registerName("initializeHID"))) {
        for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
            BOOL isTouchBar = product && [(__bridge NSString *)product isEqualToString:@"TouchBarUserDevice"];
            if (product) CFRelease(product);
            if (!isTouchBar) continue;
            BOOL added = ((BOOL (*)(id, SEL, IOHIDServiceClientRef))objc_msgSend)(client, sel_registerName("addDFRService:"), service);
            int did = ((int (*)(id, SEL))objc_msgSend)(client, sel_registerName("getDFRDisplayID"));
            if (added && did >= 0) {
                dfrClient = client;
                displayID = did;
                ready = YES;
            }
            break;
        }
    }
    CFRelease(services);
    CFRelease(system);
    return ready;
}

// 2 means the Touch Bar display is on (per TouchBarController). -1 means unknown.
static NSInteger touchBarDisplayState(void) {
    SEL get = sel_registerName("copyPropertyForKey:");
    if (!dfrClient || ![dfrClient respondsToSelector:get]) return -1;
    id value = ((id (*)(id, SEL, id))objc_msgSend)(dfrClient, get, @"DFRDisplayState");
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : -1;
}

static id coreGet(NSString *key) {
    id client = getCoreClient();
    SEL get = sel_registerName("copyPropertyForKey:andDisplay:");
    if (!client || displayID < 0 || ![client respondsToSelector:get]) return nil;
    return ((id (*)(id, SEL, id, uint64_t))objc_msgSend)(client, get, key, (uint64_t)displayID);
}

// Returns the Touch Bar brightness as 0.0-1.0, or -1 if it can't be read.
static double currentBrightness(void) {
    id props = coreGet(@"DisplayBrightness");
    id value = [props isKindOfClass:[NSDictionary class]] ? props[@"Brightness"] : nil;
    if (![value isKindOfClass:[NSNumber class]]) return -1;
    double b = [value doubleValue];
    return (isfinite(b) && b >= 0.0 && b <= 1.0) ? b : -1;
}

// Transient write: does not save a new brightness preference.
static BOOL setBrightness(double level) {
    id client = getCoreClient();
    SEL set = sel_registerName("setProperty:withKey:andDisplay:");
    if (!client || displayID < 0 || ![client respondsToSelector:set]) return NO;
    NSDictionary *props = @{@"Brightness": @(level), @"Commit": @NO, @"CommitType": @0};
    return ((BOOL (*)(id, SEL, id, id, uint64_t))objc_msgSend)(client, set, props, @"DisplayBrightness", (uint64_t)displayID);
}

static BOOL parseLevel(const char *s, double *out) {
    char *end = NULL;
    double v = strtod(s, &end);
    if (!end || *end != '\0' || !isfinite(v) || v < 0.0 || v > 1.0) return NO;
    *out = v;
    return YES;
}

static int cmdStatus(void) {
    if (!connectDFR()) {
        fprintf(stderr, "Could not connect to the Touch Bar display service.\n");
        return 1;
    }
    printf("Touch Bar display ID: %d\n", displayID);
    printf("Display state:        %ld (2 = on)\n", (long)touchBarDisplayState());
    double b = currentBrightness();
    if (b >= 0) printf("Brightness:           %.3f (0.0 to 1.0)\n", b);
    else        printf("Brightness:           unavailable\n");
    id nits = driverProperty(@"CurrentNits");
    printf("Driver CurrentNits:   %s\n", nits ? [[nits description] UTF8String] : "unavailable");
    id autoB = coreGet(@"DisplayBrightnessAuto");
    printf("DisplayBrightnessAuto: %s\n", autoB ? [[autoB description] UTF8String] : "unavailable");
    return 0;
}

static int cmdSet(double level) {
    if (!connectDFR()) {
        fprintf(stderr, "Could not connect to the Touch Bar display service.\n");
        return 1;
    }
    double before = currentBrightness();
    if (!setBrightness(level)) {
        fprintf(stderr, "Brightness write failed.\n");
        return 1;
    }
    usleep(700000);
    printf("Brightness before: %.3f, requested: %.3f, now: %.3f\n", before, level, currentBrightness());
    return 0;
}

static int cmdRun(double floorLevel, double interval) {
    printf("%s tbfloor started: floor %.2f, checking every %.2fs\n",
           [timestamp() UTF8String], floorLevel, interval);
    fflush(stdout);

    NSDate *lastLog = [NSDate distantPast];
    NSDate *lastConnectAttempt = [NSDate distantPast];
    unsigned long raisesSinceLog = 0;
    double lowestSinceLog = 1.0;

    while (1) {
        @autoreleasepool {
            if (!dfrClient || displayID < 0) {
                // Reconnect at most every 5 seconds (needed after sleep/wake).
                if ([[NSDate date] timeIntervalSinceDate:lastConnectAttempt] >= 5.0) {
                    lastConnectAttempt = [NSDate date];
                    if (connectDFR()) {
                        printf("%s connected to Touch Bar (display %d)\n", [timestamp() UTF8String], displayID);
                        fflush(stdout);
                    }
                }
            }

            if (dfrClient && displayID >= 0 && touchBarDisplayState() == 2) {
                double b = currentBrightness();
                if (b < 0) {
                    dfrClient = nil;   // read failed: reconnect next time
                } else if (b < floorLevel - 0.005) {
                    if (setBrightness(floorLevel)) {
                        raisesSinceLog++;
                        if (b < lowestSinceLog) lowestSinceLog = b;
                    } else {
                        dfrClient = nil;
                    }
                }
            }

            // Log at most once a minute so the log file stays small.
            if (raisesSinceLog > 0 && [[NSDate date] timeIntervalSinceDate:lastLog] >= 60.0) {
                printf("%s raised brightness %lu time(s) since last log (lowest seen %.3f)\n",
                       [timestamp() UTF8String], raisesSinceLog, lowestSinceLog);
                fflush(stdout);
                lastLog = [NSDate date];
                raisesSinceLog = 0;
                lowestSinceLog = 1.0;
            }
        }
        usleep((useconds_t)(interval * 1000000.0));
    }
    return 0;
}

static void usage(void) {
    fprintf(stderr,
            "Usage:\n"
            "  tbfloor status\n"
            "  tbfloor set <0.0-1.0>\n"
            "  tbfloor run [floor 0.0-1.0, default 1.0] [interval seconds, default 0.5]\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { usage(); return 2; }
        NSString *cmd = [NSString stringWithUTF8String:argv[1]];

        if ([cmd isEqualToString:@"status"]) return cmdStatus();

        if ([cmd isEqualToString:@"set"]) {
            double level;
            if (argc < 3 || !parseLevel(argv[2], &level)) { usage(); return 2; }
            return cmdSet(level);
        }

        if ([cmd isEqualToString:@"run"]) {
            double floorLevel = 1.0, interval = 0.5;
            if (argc >= 3 && !parseLevel(argv[2], &floorLevel)) { usage(); return 2; }
            if (argc >= 4) {
                interval = atof(argv[3]);
                if (!(interval >= 0.1 && interval <= 60.0)) { usage(); return 2; }
            }
            return cmdRun(floorLevel, interval);
        }

        usage();
        return 2;
    }
}
