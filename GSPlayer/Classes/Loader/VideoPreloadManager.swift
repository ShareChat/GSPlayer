//
//  VideoPreloadManager.swift
//  GSPlayer
//
//  Created by Gesen on 2019/4/20.
//  Copyright © 2019 Gesen. All rights reserved.
//

import Foundation
import UIKit

public class VideoPreloadManager: NSObject {
    
    public static let shared = VideoPreloadManager()
    
    public var preloadByteCount: Int = 1024 * 1024 // = 1M
    
    /// This property represents the threshold value of space that should be atleast available in the mobile
    public var maxCacheSizeAllowed: Int = 512
    
    public var didStart: (() -> Void)?
    public var didPause: (() -> Void)?
    public var didFinish: ((Error?) -> Void)?
    
    private var downloader: VideoDownloader?
    private var isAutoStart: Bool = true
    private var waitingQueue: [URL] = []
    private var freeDiskSpaceInMB = UIDevice.freeDiskSpaceInMB
    
    public func set(waiting: [URL]) {
        downloader = nil
        waitingQueue = waiting
        
        // Remove cache in case free memory is less than 200 MB
        if isSpaceNotAvailable() {
            try? VideoCacheManager.cleanAllCache()
        }
        
        if isAutoStart { start() }
    }
    
    public func updateFreeDiskSpaceInMB() {
        freeDiskSpaceInMB = UIDevice.freeDiskSpaceInMB
    }
    
    /// This method will help in getting the `Bool` value representing if the device memory is full or not
    /// - returns: `Bool` value representing if the device memory is full or not
    public func isSpaceNotAvailable() -> Bool {
        freeDiskSpaceInMB <= maxCacheSizeAllowed
    }
    
    func start() {
        guard downloader == nil, waitingQueue.count > 0 else {
            downloader?.resume()
            return
        }
        
        isAutoStart = true
        
        let url = waitingQueue.removeFirst()
        
        guard
            !VideoLoadManager.shared.loaderMap.keys.contains(url),
            let cacheHandler = try? VideoCacheHandler(url: url) else {
            return
        }
        
        downloader = VideoDownloader(url: url, cacheHandler: cacheHandler)
        downloader?.delegate = self
        downloader?.download(from: 0, length: preloadByteCount)
        
        if cacheHandler.configuration.downloadedByteCount < preloadByteCount {
            didStart?()
        }
    }
    
    func pause() {
        downloader?.suspend()
        didPause?()
        isAutoStart = false
    }
    
    func remove(url: URL) {
        if let index = waitingQueue.firstIndex(of: url) {
            waitingQueue.remove(at: index)
        }
        
        if downloader?.url == url {
            downloader = nil
        }
    }
    
}

extension VideoPreloadManager: VideoDownloaderDelegate {
    
    public func downloader(_ downloader: VideoDownloader, didReceive response: URLResponse) {
        
    }
    
    public func downloader(_ downloader: VideoDownloader, didReceive data: Data) {
        
    }
    
    public func downloader(_ downloader: VideoDownloader, didFinished error: Error?) {
        self.downloader = nil
        start()
        didFinish?(error)
    }
    
}

// MARK: Device Disk space
extension UIDevice {
    
    static var totalDiskSpaceInMB: Int64 = {
        return UIDevice.totalDiskSpaceInBytes / (1024 * 1024)
    }()

    static var freeDiskSpaceInMB: Int64 {
        return UIDevice.freeDiskSpaceInBytes / (1024 * 1024)
    }

    static var usedDiskSpaceInMB: Int64 {
        return UIDevice.usedDiskSpaceInBytes / (1024 * 1024)
    }

    static var totalDiskSpaceInBytes: Int64 {
        guard let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory() as String),
            let space = (systemAttributes[FileAttributeKey.systemSize] as? NSNumber)?.int64Value else { return 0 }
        return space
    }

    static var freeDiskSpaceInBytes: Int64 {
        if #available(iOS 11.0, *) {
            if let space = try? URL(fileURLWithPath: NSHomeDirectory() as String).resourceValues(forKeys: [URLResourceKey.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
                return space
            } else {
                return 0
            }
        } else {
            if let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory() as String),
                let freeSpace = (systemAttributes[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value {
                return freeSpace
            } else {
                return 0
            }
        }
    }

    static var usedDiskSpaceInBytes: Int64 {
        return totalDiskSpaceInBytes - freeDiskSpaceInBytes
    }
}
