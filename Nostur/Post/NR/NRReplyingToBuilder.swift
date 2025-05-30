//
//  NRReplyingToBuilder.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import CoreData

class NRReplyingToBuilder {
    
    static let shared = NRReplyingToBuilder()

    // TODO: Add replyTo pfpUrl or pubkey or nrContact here also, and return, but only if missingReplyTo
    func replyingToUsernamesMarkDownString(_ event: Event) -> String? {
        guard event.replyToId != nil || event.replyTo != nil else { return nil }
        
        if let replyTo = event.replyTo, replyTo.kind == 30023 {
            guard let articleTitle = replyTo.eventTitle else {
                return "Replying to article"
            }
            return String(localized:"Replying to: \(articleTitle)", comment: "Shown when replying to an article (Replying to: (article title)")
        }
        
        if let replyTo = event.replyTo, replyTo.kind == 443 {
            guard let url = replyTo.fastTags.first(where: { $0.0 == "r" })?.1 else {
                return "Commenting on website"
            }
            return String(localized:"Commenting on \(url)", comment: "Shown when adding a comment to a website")
        }
        
        let tags = event.fastTags
        guard tags.count < 50 else { return String(localized:"Replying to \(tags.count) people", comment: "Shown in a post, Replying to (X) people ") }

        let pTags = Set(tags.filter { $0.0 == "p" }.map { $0.1 })
        if (pTags.count > 6) {
            let pTagsAsStrings = pTags.prefix(4).map { pubkey in
                let username = contactUsername(fromPubkey: pubkey, event: event)
                    .escapeMD()
                return "[@\(username)](nostur:p:\(pubkey))"
            }
            return String(localized:"Replying to: \(pTagsAsStrings.joined(separator: ", ")) and \(pTags.count-4) others", comment: "Shown in a post, Replying: (names) and (x) others")
        }
        else if (!pTags.isEmpty) {
            let pTagsAsStrings = pTags.map { pubkey in
                let username = contactUsername(fromPubkey: pubkey, event: event)
                    .escapeMD()
                return "[@\(username)](nostur:p:\(pubkey))"
            }
            return String(localized:"Replying to: \(pTagsAsStrings.formatted(.list(type: .and)))", comment:"Shown in a post, Replying to (names)")
        }
        else {
            return String(localized:"Replying to...", comment:"Shown in a post when replying but the name is missing")
        }
    }

}

func contactUsername(fromPubkey pubkey: String, event: Event? = nil) -> String {
    if let anyName = PubkeyUsernameCache.shared.retrieveObject(at: pubkey) {
        return anyName
    }
    
    if let anyName = AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.anyName {
        return anyName
    }
    
    if let anyName = NRContactCache.shared.retrieveObject(at: pubkey)?.anyName {
        PubkeyUsernameCache.shared.setObject(for: pubkey, value: anyName)
        return anyName
    }
    
    if let event {
        if let contact = event.contact, contact.pubkey == pubkey {
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
            return contact.anyName
        }
        if let contact = event.replyTo?.contact, pubkey == contact.pubkey {
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
            return contact.anyName
        }
    }
    if !Thread.isMainThread {
        if let contact = EventRelationsQueue.shared.getAwaitingBgContacts().first(where: { $0.pubkey == pubkey }) {
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
            return contact.anyName
        }
    }
    
    if let event {
        if let context = event.managedObjectContext {
#if DEBUG
            L.og.debug("🔴🔴 Expensive Contact.fetchByPubkey event.managedObjectContext \(pubkey)")
#endif
            if let contact = Contact.fetchByPubkey(pubkey, context: context) {
#if DEBUG
                L.og.debug("🔴🔴 Expensive Contact.fetchByPubkey \(pubkey) - \(contact.anyName)")
#endif
                PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
                return contact.anyName
            }
        }
    }
    else if !Thread.isMainThread {
#if DEBUG
        L.og.debug("🔴🔴 Expensive Contact.fetchByPubkey !Thread.isMainThread \(pubkey)")
#endif
        if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
            #if DEBUG
            L.og.debug("🔴🔴 Expensive Contact.fetchByPubkey \(pubkey) - \(contact.anyName)")
            #endif
            PubkeyUsernameCache.shared.setObject(for: pubkey, value: contact.anyName)
            return contact.anyName
        }
    }
    
    // Save the cache miss so we don't try again for no reason
    PubkeyUsernameCache.shared.setObject(for: pubkey, value: "...")
    return "..."
}
