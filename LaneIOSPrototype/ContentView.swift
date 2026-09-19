import SwiftUI

private let accent=Color(red:0.55,green:0.31,blue:0.98)

struct ContentView:View{
 @EnvironmentObject var s:LaneSession
 var body:some View{TabView{HomeView().tabItem{Label("Home",systemImage:"house.fill")};SearchView().tabItem{Label("Search",systemImage:"magnifyingglass")};ProfileView().tabItem{Label("Profile",systemImage:"person.crop.circle")}}.tint(accent)}
}
struct HomeView:View{@EnvironmentObject var s:LaneSession;var body:some View{NavigationStack{VStack(spacing:18){Image(systemName:"waveform.circle.fill").font(.system(size:72)).foregroundStyle(accent);Text("Lane").font(.largeTitle.bold());Text(s.isGuest ? "Sign in with Telegram to use the Lane backend." : "Ready to play").foregroundStyle(.secondary);if let t=s.currentTrack{VStack{Text(t.title).font(.headline);Text(t.subtitle).foregroundStyle(.secondary);Button(s.isPlaying ? "Pause":"Play"){s.togglePlayback()}.buttonStyle(.borderedProminent)}};Spacer()}.padding().navigationTitle("Home")}}}
struct SearchView:View{@EnvironmentObject var s:LaneSession;@State var q="";var body:some View{NavigationStack{VStack{HStack{TextField("Search music",text:$q).textFieldStyle(.roundedBorder).onSubmit{s.search(q)};Button("Search"){s.search(q)}}.padding();if s.busy{ProgressView()};List(s.tracks){t in Button{s.requestStream(for:t)}label:{HStack{AsyncImage(url:URL(string:t.coverURL ?? "")){im in im.resizable().scaledToFill()}placeholder:{Color.secondary.opacity(0.15)}.frame(width:52,height:52).clipShape(RoundedRectangle(cornerRadius:10));VStack(alignment:.leading){Text(t.title).foregroundStyle(.primary);Text(t.subtitle).font(.caption).foregroundStyle(.secondary)}}}}}.navigationTitle("Search")}}}
struct ProfileView:View{@EnvironmentObject var s:LaneSession;@State var token="";var body:some View{NavigationStack{Form{Section("Telegram / Lane token"){SecureField("Bearer token",text:$token);Button("Save token"){s.saveToken(token)};if !s.isGuest{Button("Log out",role:.destructive){s.logout()}}}Section("Build"){Text("Lane iOS cloud build").foregroundStyle(.secondary)}if !s.message.isEmpty{Section("Status"){Text(s.message)}}}.navigationTitle("Profile").onAppear{token=s.token}}}}
