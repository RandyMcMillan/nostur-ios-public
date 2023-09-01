//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var theme:Theme
    @State var fg:FollowingGuardian = .shared // If we put this on NosturApp the preview environment keeps loading it
    @State var fn:FollowerNotifier = .shared 
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @State var navPath = NavigationPath()
    @State var account:Account?
    @State var showingNewNote = false
    @EnvironmentObject var sm:SideBarModel
    @ObservedObject var settings:SettingsStore = .shared
    @State var showingOtherContact:NRContact? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
//    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            if let account {
                FollowingAndExplore(account: account)
                    .background(theme.listBackground)
                    .withNavigationDestinations()
                    .overlay(alignment: .bottomTrailing) {
                        NewNoteButton(showingNewNote: $showingNewNote)
                            .padding([.top, .leading, .bottom], 10)
                            .padding([.trailing], 25)
                    }
                    .overlay(alignment: .bottom) {
                        if settings.statusBubble {
                            ProcessingStatus()
                                .opacity(0.85)
                                .padding(.bottom, 10)
                        }
                    }
                    .sheet(isPresented: $showingNewNote) {
                        NavigationStack {
                            if account.isNC, let nsecBunker = NosturState.shared.nsecBunker {
                                WithNSecBunkerConnection(nsecBunker: nsecBunker) {
                                    NewPost()
                                }
                            }
                            else {
                                NewPost()
                            }
                        }
                    }
                    .toolbar {
                        if let account = self.account, !sm.showSidebar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                PFP(pubkey: account.publicKey, account: account, size:30)
                                    .onTapGesture {
                                        sm.showSidebar.toggle()
                                    }
                                    .accessibilityLabel("Account menu")
                            }
                        }
                        ToolbarItem(placement: .principal) {
                            HStack {
                                if let showingOtherContact = showingOtherContact {
                                    HStack(spacing: 6) {
                                        PFP(pubkey: showingOtherContact.pubkey, nrContact: showingOtherContact, size: 30)
                                            .frame(height:30)
                                            .clipShape(Circle())
                                            .onTapGesture {
                                                sendNotification(.shouldScrollToTop)
                                            }
                                        
                                        Image(systemName: "multiply.circle.fill")
                                            .onTapGesture {
                                                guard let account = NosturState.shared.account else { return }
                                                self.showingOtherContact = nil
                                                LVMManager.shared.followingLVM(forAccount: account)
                                                    .revertBackToOwnFeed()
                                            }
                                    }
                                    .offset(x: 18)
                                        
                                }
                                else {
                                    Image("NosturLogo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height:30)
                                        .clipShape(Circle())
                                        .onTapGesture {
                                            print("ok3")
                                            sendNotification(.shouldScrollToTop)
                                        }
                                }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Image(systemName: "gearshape")
                                .foregroundColor(theme.accent)
                                .onTapGesture {
                                    sendNotification(.showFeedToggles)
                                }
                        }
                    }
            }
        }
        .onReceive(receiveNotification(.showingSomeoneElsesFeed)) { notification in
            let nrContact = notification.object as! NRContact
            showingOtherContact = nrContact
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! Account
            guard self.account != account else { return }
            self.account = account
            if selectedSubTab != "Following" {
                selectedSubTab = "Following"
            }
        }
        .onAppear {
            guard let account = NosturState.shared.account else { return }
            self.account = account
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD || horizontalSizeClass == .compact else { return }
            guard selectedTab == "Main" else { return }
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.navigateToOnMain)) { notification in
            let destination = notification.object as! NavigationDestination
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.didTapTab)) { notification in
            guard let tabName = notification.object as? String, tabName == "Main" else { return }
            if navPath.count == 0 {
                sendNotification(.shouldScrollToFirstUnread)
            }
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            // No need to clear if we are already at root
            guard navPath.count > 0 else { return }
            
            // if notification.object is not empty/nil
            if let tab = notification.object as? String, tab == "Main" {
                navPath.removeLast(navPath.count)
            }
            else if notification.object == nil {
                // if empty/nil, we always clear
                navPath.removeLast(navPath.count)
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadFollowers()
        }) {
            MainView()
        }
    }
}
