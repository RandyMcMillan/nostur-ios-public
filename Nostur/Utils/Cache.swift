//
//  Cache.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import SwiftUI

typealias EventId = String

struct PubkeyUsernameCache {
    static let shared: LRUCache2<String, String> = {
        let cache = LRUCache2<String, String>(countLimit: 2500)
        return cache
    }()
}

struct NRContactCache {
    static let shared: LRUCache2<String, NRContact> = {
        let cache = LRUCache2<String, NRContact>(countLimit: 1000)
        return cache
    }()
}

struct EventCache {
    static let shared: LRUCache2<String, Event> = {
        let cache = LRUCache2<String, Event>(countLimit: 500)
        return cache
    }()
}


class LinkPreviewCache {
    
    public let cache = LRUCache2<URL, [String: String]>(countLimit: 500)
    
    public let metaTagsRegex = try! NSRegularExpression(pattern: #"<meta\s+(?:property=|name=)"(?:og|twitter):(.*?)"\s+content="([^"]+)(?:"\s|"[^>]*?\/?>)"#, options: .caseInsensitive)
    
    public let titleRegex = try! NSRegularExpression(pattern: "<title(?:.*)>([^<]*)</title>", options: .caseInsensitive)
    
    static let shared = LinkPreviewCache()
    
    private init() {}
}

class AccountCache {
    
    // For every post render we need to hit the database to see if we have bookmarked, liked, replied or zapped. Better cache that here.
    
    public let pubkey: String
    
    private var bookmarkedIds: [String: Color] = [:]
    private var likedIds: Set<String> = []
    private var repostedIds: Set<String> = []
    private var repliedToIds: Set<String> = []
    private var zappedIds: Set<String> = []
    private var reactionIds: [String: Set<String>] = [:]
    
    private var initializedCaches: Set<String> = []
    
    init(_ pubkey: String) {
        self.pubkey = pubkey
        initBookmarked()
        initReactions(pubkey)
        initReplied(pubkey)
        initReposted(pubkey)
        initZapped(pubkey)
    }
    
    public var cacheIsReady: Bool {
        initializedCaches.count == 6
    }
    
    
    
    
    public func getBookmarkColor(_ eventId: String) -> Color? {
        return bookmarkedIds[eventId]
    }
    
    public func addBookmark(_ eventId: String, color: Color) {
        bookmarkedIds[eventId] = color
    }
    
    public func removeBookmark(_ eventId: String) {
        bookmarkedIds[eventId] = nil
    }
    
    
    
    public func isLiked(_ eventId: String) -> Bool {
        return likedIds.contains(eventId)
    }
    
    public func addLike(_ eventId: String) {
        likedIds.insert(eventId)
    }
    
    public func removeLike(_ eventId: String) {
        likedIds.remove(eventId)
    }
    
    
    
    public func hasReaction(_ eventId: String, reactionType: String) -> Bool {
        return reactionIds[reactionType]?.contains(eventId) ?? false
    }
    
    public func addReaction(_ eventId: String, reactionType: String) {
        if reactionIds[reactionType] == nil {
            reactionIds[reactionType] = [eventId]
        }
        else {
            reactionIds[reactionType]?.insert(eventId)
        }
    }
    
    public func removeReaction(_ eventId: String, reactionType: String) {
        reactionIds[reactionType]?.insert(eventId)
    }
    
    
    
    
    public func isRepliedTo(_ eventId: String) -> Bool {
        return repliedToIds.contains(eventId)
    }
    
    public func addRepliedTo(_ eventId: String) {
        repliedToIds.insert(eventId)
    }
    
    public func removeRepliedTo(_ eventId: String) {
        repliedToIds.remove(eventId)
    }
    
    
    
    
    public func isReposted(_ eventId: String) -> Bool {
        return repostedIds.contains(eventId)
    }
    
    public func addReposted(_ eventId: String) {
        repostedIds.insert(eventId)
    }
    
    public func removeReposted(_ eventId: String) {
        repostedIds.remove(eventId)
    }
    
    
    
    
    public func isZapped(_ eventId: String) -> Bool {
        return zappedIds.contains(eventId)
    }
    
    public func addZapped(_ eventId: String) {
        zappedIds.insert(eventId)
    }
    
    public func removeZapped(_ eventId: String) {
        zappedIds.remove(eventId)
    }
    
    
    
    
    
    
    private func initBookmarked() {
        let bookmarks = Bookmark.fetchAll(context: bg())
        for bookmark in bookmarks {
            guard let eventId = bookmark.eventId else { continue }
            self.bookmarkedIds[eventId] = bookmark.color
        }
        self.initializedCaches.insert("bookmarks")
    }
    
    private func initReactions(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == 7", pubkey)
        let allReactions = (try? bg().fetch(fr)) ?? []
        
        var likedIds: Set<String> = []
        var reactionIds: [String: Set<String>] = [:]
        
        for reaction in allReactions {
            guard let reactionToId = reaction.reactionToId else {
                continue
            }
            if reaction.content == "+" {
                likedIds.insert(reactionToId)
            }
            else {
                let reactionType = reaction.content ?? "+"
                if reactionIds[reactionType] == nil {
                    reactionIds[reactionType] = [reactionToId]
                }
                else {
                    reactionIds[reactionType]?.insert(reactionToId)
                }
            }
        }

        self.likedIds = likedIds
        self.reactionIds = reactionIds
        self.initializedCaches.insert("likes")
        self.initializedCaches.insert("reactions")
    }
    
    private func initReplied(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == 1", pubkey)
        let allRepliedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.replyToId })
        self.repliedToIds = allRepliedIds
        self.initializedCaches.insert("replies")
    }
    
    private func initReposted(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 6 AND pubkey == %@", pubkey)
        let allRepostedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.firstQuoteId })
    
        self.repostedIds = allRepostedIds
        self.initializedCaches.insert("reposts")
    }
    
    private func initZapped(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 9734 AND pubkey == %@", pubkey)
        let allZappedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.firstE() })

        self.zappedIds = allZappedIds
        self.initializedCaches.insert("zaps")
    }
    
}
