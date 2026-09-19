import SwiftUI

private let accent = Color(red: 0.55, green: 0.31, blue: 0.98)

struct ContentView: View {
    @EnvironmentObject var session: LaneSession

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(accent)
    }
}

struct HomeView: View {
    @EnvironmentObject var session: LaneSession

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(accent)

                Text("Lane")
                    .font(.largeTitle.bold())

                Text(session.isGuest ? "Sign in with Telegram to use the Lane backend." : "Ready to play")
                    .foregroundStyle(.secondary)

                if let track = session.currentTrack {
                    VStack {
                        Text(track.title).font(.headline)
                        Text(track.subtitle).foregroundStyle(.secondary)
                        Button(session.isPlaying ? "Pause" : "Play") {
                            session.togglePlayback()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var session: LaneSession
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    TextField("Search music", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { session.search(query) }

                    Button("Search") {
                        session.search(query)
                    }
                }
                .padding()

                if session.busy {
                    ProgressView()
                }

                List(session.tracks) { track in
                    Button {
                        session.requestStream(for: track)
                    } label: {
                        HStack {
                            AsyncImage(url: URL(string: track.coverURL ?? "")) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading) {
                                Text(track.title).foregroundStyle(.primary)
                                Text(track.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var session: LaneSession
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Telegram / Lane token") {
                    SecureField("Bearer token", text: $token)

                    Button("Save token") {
                        session.saveToken(token)
                    }

                    if !session.isGuest {
                        Button("Log out", role: .destructive) {
                            session.logout()
                        }
                    }
                }

                Section("Build") {
                    Text("Lane iOS cloud build")
                        .foregroundStyle(.secondary)
                }

                if !session.message.isEmpty {
                    Section("Status") {
                        Text(session.message)
                    }
                }
            }
            .navigationTitle("Profile")
            .onAppear {
                token = session.token
            }
        }
    }
}
