import Foundation

struct TrackStreamingResult: Decodable { let url:String; let trackId:String; let playbackToken:String; let ttl:Int64 }
struct LaneTokenResponse: Decodable { let token:String; let isFirstAuth:Bool }
struct LaneCombinedSearchResponse: Decodable { let results:[LaneSearchResultItem]; let searchToken:String? }
struct LaneSearchResultItem: Decodable, Identifiable { let type:String; let track:TrackData?; let platform:String?; var id:String{"\(type)|\(track?.songId ?? UUID().uuidString)"} }
struct TrackData: Decodable { let songId:String; let platform:String; let title:String; let artistsDisplayedName:String; let coverUrl:String?; let duration:String?; let genre:String? }
struct TrackCandidate: Identifiable, Hashable { let id=UUID(); let title:String; let subtitle:String; let rawID:String?; let trackID:String?; let refID:String?; let stream:String?; let coverURL:String? }

enum JSONProbe {
 static func tracks(_ value:Any?)->[TrackCandidate]{ var out:[TrackCandidate]=[];walk(value,&out);var seen=Set<String>();return out.filter{seen.insert("\($0.title)|\($0.trackID ?? $0.rawID ?? "")|\($0.refID ?? "")").inserted}}
 static func token(_ value:Any?)->String?{if let d=value as? [String:Any]{for key in ["token","accessToken","access_token","bearerToken"]{if let s=d[key] as? String,!s.isEmpty{return s}};for(_,v) in d{if let s=token(v){return s}}}else if let a=value as? [Any]{for v in a{if let s=token(v){return s}}};return nil}
 static func firstHTTPURL(_ value:Any?)->String?{if let s=value as? String,let u=URL(string:s),["http","https"].contains(u.scheme?.lowercased() ?? ""){return s};if let d=value as? [String:Any]{for(_,v) in d{if let s=firstHTTPURL(v){return s}}};if let a=value as? [Any]{for v in a{if let s=firstHTTPURL(v){return s}}};return nil}
 private static func walk(_ value:Any?,_ out:inout [TrackCandidate]){if let d=value as? [String:Any]{let title=str(d,["title","name","trackName","track_name"]);let artist=str(d,["artistsDisplayedName","artist","artistName","artist_name","author","username"]);let trackID=str(d,["songId","trackId","track_id"]),refID=str(d,["refId","ref_id"]),rid=str(d,["id","uuid","key"]);let stream=str(d,["stream","streamUrl","stream_url","audioUrl","audio_url","url"]);if let title,trackID != nil || rid != nil || artist != nil{out.append(.init(title:title,subtitle:artist ?? "Track",rawID:rid,trackID:trackID,refID:refID,stream:http(stream),coverURL:http(str(d,["coverUrl","cover_url","artworkUrl","image"]))))};for(_,v) in d{walk(v,&out)}}else if let a=value as? [Any]{for v in a{walk(v,&out)}}}
 private static func str(_ d:[String:Any],_ keys:[String])->String?{for k in keys{if let s=d[k] as? String,!s.isEmpty{return s};if let n=d[k] as? NSNumber{return n.stringValue}};return nil}
 private static func http(_ s:String?)->String?{guard let s,let u=URL(string:s),["http","https"].contains(u.scheme?.lowercased() ?? "") else{return nil};return s}
}
struct LocalPlaylist:Identifiable,Codable,Hashable{var id:UUID=UUID();var name:String;var trackKeys:[String]=[]}
struct LaneFeature:Identifiable,Hashable{let id=UUID();let title:String;let subtitle:String;let icon:String}
struct TrackStatsDTO:Decodable{let likesCount:Int64;let commentsCount:Int64}
