//
//  ContentView.swift
//  Poplur2025
//
//  Created by Apptist Inc. on 2025-08-03.
//

import SwiftUI
import SpriteKit

struct HomeView: View {
    var body: some View {
        TabView {
            // Map View Tab
            MapView()
                .tabItem {
                    Image(systemName: "map")
                    Text("Map")
                }
            
            // Feed View Tab
            FeedView()
                .tabItem {
                    Image(systemName: "list.dash")
                    Text("Feed")
                }
            
            // Profile View Tab
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
        }
    }
}

#Preview {
    HomeView()
}
