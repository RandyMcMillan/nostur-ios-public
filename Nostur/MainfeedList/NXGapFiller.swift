//
//  NXGapFiller.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/08/2024.
//

import SwiftUI

// Catch up - resume feed
// Fetch posts since last time in X hour windows
// Wait Y seconds per window
// Can't know if fetch window has no posts or connection failure
// So before advancing to next window, make sure we have connection
// Note: don't use for "older"
class NXGapFiller {
    private var since: Int64
    private var windowSize: Int // Hours
    private var timeout: Double // Seconds
    private var currentGap: Int // used to calculate nextGapSince
    private weak var columnVM: NXColumnViewModel?
    private var backlog: Backlog
    
    private var windowStart: Int { // Depending on older or not we use start/end as since/until
        return Int(since) + (currentGap * 3600 * windowSize)
    }
    private var windowEnd: Int { // Depending on older or not we use start/end as since/until
        windowStart + (3600 * windowSize)
    }
    
    public init(since: Int64, windowSize: Int = 4, timeout: Double = 2, currentGap: Int = 0, columnVM: NXColumnViewModel) {
        self.since = since
        self.windowSize = windowSize
        self.timeout = timeout
        self.currentGap = currentGap
        self.columnVM = columnVM
        self.backlog = Backlog(timeout: timeout, auto: true)
    }
    
    @MainActor
    public func fetchGap(since: Int64, currentGap: Int) {
        guard let columnVM, let config = columnVM.config else { return }
        self.since = since
        self.currentGap = currentGap
        
        // Check connection?
        guard ConnectionPool.shared.anyConnected else {
            L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") Not connected, skipping fetchGap")
            return
        }
        
        // Check if paused
        guard !columnVM.isPaused else {
            L.og.debug("☘️☘️🔴🔴 \(columnVM.id ?? "?") paused, skipping fetchGap")
            return
        }
                
        // send REQ
        if let (cmd, subId) = columnVM.getFillGapReqStatement(config, since: windowStart, until: windowEnd) {
            
            let reqTask = ReqTask(
                timeout: 15.0,
                subscriptionId: subId,
                reqCommand: { [weak self] _ in
                    guard let self else { return }
                    L.og.debug("☘️☘️⏭️ \(columnVM.id ?? "?") currentGap: \(self.currentGap) \(Date(timeIntervalSince1970: TimeInterval(self.windowStart)).formatted()) - \(Date(timeIntervalSince1970: TimeInterval(self.windowEnd)).formatted()) now=\(Date.now.formatted())")
                    cmd()
                },
                processResponseCommand: { [weak self] _, _, _ in
                    guard let self else { return }
                    self.columnVM?.refreshedAt = Int64(Date().timeIntervalSince1970)
                    self.columnVM?.loadLocal(config)
                    
                    if self.windowStart < Int(Date().timeIntervalSince1970) {
                        self.fetchGap(since: self.since, currentGap: self.currentGap + 1) // next gap (no since param)
                    }
                    else {
                        self.currentGap = 0
                    }
                },
                timeoutCommand: { subId in
                    L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") timeout in fetchGap \(subId)")
                    Task { @MainActor in
                        self.columnVM?.loadLocal(config)
                    }
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
        }
    }
}
