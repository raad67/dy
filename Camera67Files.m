#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@interface C67FilesObserver : NSObject <PHPhotoLibraryChangeObserver, UIDocumentPickerDelegate>
@property (nonatomic, strong) PHFetchResult<PHAsset *> *fetchResult;
@property (nonatomic, assign) BOOL showingPrompt;
+ (instancetype)shared;
- (void)start;
@end

@implementation C67FilesObserver

+ (instancetype)shared {
    static C67FilesObserver *observer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ observer = [C67FilesObserver new]; });
    return observer;
}

- (void)start {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus result) {
            if (result == PHAuthorizationStatusAuthorized || result == PHAuthorizationStatusLimited) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self beginObserving]; });
            }
        }];
        return;
    }
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
        [self beginObserving];
    }
}

- (void)beginObserving {
    if (self.fetchResult) return;
    PHFetchOptions *options = [PHFetchOptions new];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    self.fetchResult = [PHAsset fetchAssetsWithOptions:options];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    PHFetchResult<PHAsset *> *oldResult = self.fetchResult;
    if (!oldResult) return;
    PHFetchResultChangeDetails<PHAsset *> *details = [changeInstance changeDetailsForFetchResult:oldResult];
    if (!details) return;

    NSArray<PHAsset *> *inserted = details.insertedObjects;
    self.fetchResult = details.fetchResultAfterChanges;
    if (inserted.count == 0) return;

    PHAsset *newAsset = [[inserted filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PHAsset *asset, NSDictionary *bindings) {
        return asset.creationDate && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 30.0;
    }]] firstObject];
    if (!newAsset) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        [self offerSaveForAsset:newAsset];
    });
}

- (UIWindow *)activeWindow {
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in windowScene.windows) if (window.isKeyWindow) return window;
    }
    return application.keyWindow;
}

- (UIViewController *)topViewController {
    UIViewController *controller = self.activeWindow.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    return controller;
}

- (void)offerSaveForAsset:(PHAsset *)asset {
    if (self.showingPrompt) return;
    UIViewController *presenter = [self topViewController];
    if (!presenter) return;
    self.showingPrompt = YES;

    NSString *kind = (asset.mediaType == PHAssetMediaTypeVideo) ? @"فيديو" : @"صورة";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"تم التقاط %@", kind]
                                                                   message:@"هل تريد حفظ نسخة في تطبيق الملفات؟"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ في الملفات" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        weakSelf.showingPrompt = NO;
        [weakSelf exportAsset:asset];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"لاحقاً" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        weakSelf.showingPrompt = NO;
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (PHAssetResource *)resourceForAsset:(PHAsset *)asset {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    BOOL video = (asset.mediaType == PHAssetMediaTypeVideo);
    for (PHAssetResource *resource in resources) {
        if (video && (resource.type == PHAssetResourceTypeVideo || resource.type == PHAssetResourceTypeFullSizeVideo)) return resource;
        if (!video && (resource.type == PHAssetResourceTypePhoto || resource.type == PHAssetResourceTypeFullSizePhoto)) return resource;
    }
    return resources.firstObject;
}

- (void)exportAsset:(PHAsset *)asset {
    PHAssetResource *resource = [self resourceForAsset:asset];
    if (!resource) {
        [self showError:@"تعذر العثور على الملف الأصلي."];
        return;
    }

    NSString *originalName = resource.originalFilename.lastPathComponent;
    if (originalName.length == 0) originalName = (asset.mediaType == PHAssetMediaTypeVideo) ? @"Camera67-Video.mov" : @"Camera67-Photo.heic";
    NSString *name = [NSString stringWithFormat:@"Camera67-%@-%@", NSUUID.UUID.UUIDString, originalName];
    NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];

    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = YES;
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:resource toFile:destination options:options completionHandler:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self showError:[NSString stringWithFormat:@"فشل تجهيز الملف: %@", error.localizedDescription ?: @"خطأ غير معروف"]];
                return;
            }
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[destination] asCopy:YES];
            picker.delegate = self;
            UIViewController *presenter = [self topViewController];
            if (presenter) [presenter presentViewController:picker animated:YES completion:nil];
        });
    }];
}

- (void)showError:(NSString *)message {
    UIViewController *presenter = [self topViewController];
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Camera67" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

__attribute__((constructor)) static void Camera67FilesEntry(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
            if (![bundleID isEqualToString:@"com.apple.camera67"]) return;
            [[C67FilesObserver shared] start];
        });
    }
}
