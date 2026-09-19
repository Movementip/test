import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class LaneSession: ObservableObject {
 @Published var token=KeychainStore.load(account:"lane.token") ?? ""
 @Published var tracks:[TrackCandidate]=[]
 @Published var currentTrack:TrackCandidate?
 @Published var isPlaying=false
 @Published var busy=false
 @Published var message=""
 let baseURL="https://laneapi.com"
 private var player:AVPlayer?
 var isGuest:Bool { token.isEmpty }

 func search(_ q:String){
  let q=q.trimmingCharacters(in:.whitespacesAndNewlines);guard !q.isEmpty,!token.isEmpty else{return};busy=true
  Task{defer{busy=false};do{await LaneAPI.shared.setBase(baseURL);let r=try await LaneAPI.shared.search(token:token,query:q,platform:"spotify",version:"2");tracks=r.results.compactMap{guard let t=$0.track else{return nil};return TrackCandidate(title:t.title,subtitle:t.artistsDisplayedName,rawID:nil,trackID:t.songId,refID:nil,stream:nil,coverURL:t.coverUrl)}}catch{message=error.localizedDescription}}
 }
 func requestStream(for t:TrackCandidate){
  guard let id=t.trackID,!token.isEmpty else{return};currentTrack=t;busy=true
  Task{defer{busy=false};do{await LaneAPI.shared.setBase(baseURL);let r=try await LaneAPI.shared.stream(token:token,trackId:id,refId:t.refID,quality:nil);play(r.url)}catch{message=error.localizedDescription}}
 }
 func play(_ value:String){guard let u=URL(string:value) else{return};do{try AVAudioSession.sharedInstance().setCategory(.playback);try AVAudioSession.sharedInstance().setActive(true)}catch{};player=AVPlayer(url:u);player?.play();isPlaying=true}
 func togglePlayback(){if isPlaying{player?.pause()}else{player?.play()};isPlaying.toggle()}
 func logout(){token="";KeychainStore.delete(account:"lane.token");tracks=[];player?.pause();isPlaying=false}
 func saveToken(_ value:String){token=value.trimmingCharacters(in:.whitespacesAndNewlines);KeychainStore.save(token,account:"lane.token")}
}
