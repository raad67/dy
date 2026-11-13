// Camera67Probe: diagnostic-only injection for com.apple.camera67.
// Inventories Objective-C classes/selectors related to camera capture and ProRes.
// It does not bypass storage checks or change hardware capabilities.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <objc/runtime.h>

static int contains_ci(const char *s, const char *needle) {
    if (!s || !needle || !*needle) return 0;
    size_t n = strlen(needle);
    for (; *s; ++s) {
        size_t i = 0;
        while (i < n && s[i] &&
               ((s[i] >= 'A' && s[i] <= 'Z' ? s[i] + 32 : s[i]) ==
                (needle[i] >= 'A' && needle[i] <= 'Z' ? needle[i] + 32 : needle[i]))) ++i;
        if (i == n) return 1;
    }
    return 0;
}

static int matches_any(const char *s, const char *const *words, size_t count) {
    for (size_t i = 0; i < count; ++i)
        if (contains_ci(s, words[i])) return 1;
    return 0;
}

__attribute__((constructor))
static void camera67_probe_init(void) {
    const char *bundle = getenv("CFBundleIdentifier");
    (void)bundle;

    char path[1024];
    const char *tmp = getenv("TMPDIR");
    if (!tmp || !*tmp) tmp = "/tmp";
    snprintf(path, sizeof(path), "%s/Camera67Probe.txt", tmp);

    FILE *f = fopen(path, "w");
    if (!f) return;

    fprintf(f, "Camera67Probe loaded\nPID=%d\n", getpid());
    fprintf(f, "Diagnostic only: no capture or storage behavior is changed.\n\n");

    int count = objc_getClassList(NULL, 0);
    if (count <= 0 || count > 100000) {
        fprintf(f, "objc_getClassList returned %d\n", count);
        fclose(f);
        return;
    }

    Class *classes = calloc((size_t)count, sizeof(Class));
    if (!classes) {
        fprintf(f, "Class allocation failed\n");
        fclose(f);
        return;
    }

    int actual = objc_getClassList(classes, count);
    const char *class_words[] = {"camera", "capture", "record", "prores", "video", "movie", "storage", "format"};
    const char *selector_words[] = {"prores", "record", "format", "frame", "storage", "external", "codec",
                                    "device", "capture", "video", "movie", "supported", "quality", "resolution", "fps"};
    int written = 0;
    fprintf(f, "Registered classes=%d\n\n", actual);

    for (int i = 0; i < actual; ++i) {
        const char *name = class_getName(classes[i]);
        if (!matches_any(name, class_words, sizeof(class_words) / sizeof(class_words[0]))) continue;

        fprintf(f, "CLASS %s\n", name ? name : "(null)");
        unsigned int method_count = 0;
        Method *methods = class_copyMethodList(classes[i], &method_count);
        for (unsigned int j = 0; methods && j < method_count; ++j) {
            const char *selector = sel_getName(method_getName(methods[j]));
            if (matches_any(selector, selector_words, sizeof(selector_words) / sizeof(selector_words[0]))) {
                fprintf(f, "  - %s\n", selector ? selector : "(null)");
                ++written;
            }
        }
        free(methods);
    }

    fprintf(f, "\nRelevant selectors written=%d\n", written);
    free(classes);
    fclose(f);
}
