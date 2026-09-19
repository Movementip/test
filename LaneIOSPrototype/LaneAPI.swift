import Foundation

struct APIResult {
    let status: Int; let headers: [AnyHashable:Any]; let data: Data
    var pretty:String { if let o=try? JSONSerialization.jsonObject(with:data),let d=try? JSONSerialization.data(withJSONObject:o,options:[.prettyPrinted,.sortedKeys]),let s=String(data:d,encoding:.utf8){return s}; return String(data:data,encoding:.utf8) ?? "<binary: \(data.count) bytes>" }
    var json:Any? { try? JSONSerialization.jsonObject(with:data) }
}
enum LaneAPIError:LocalizedError { case invalidURL,nonHTTP,http(Int,String),decoding(String); var errorDescription:String? { switch self {case .invalidURL:return "Invalid URL";case .nonHTTP:return "Non-HTTP response";case let .http(c,b):return "HTTP \(c): \(b)";case let .decoding(s):return "Decode error: \(s)"} } }

actor LaneAPI {
 static let shared=LaneAPI(); private var base=URL(string:"https://laneapi.com")!
 func setBase(_ value:String){if let u=URL(string:value){base=u}}
 private func build(path:String,method:String,token:String?,query:[URLQueryItem],json:[String:Any]?) throws -> URLRequest {
  let clean=path.trimmingCharacters(in:CharacterSet(charactersIn:"/")); guard var c=URLComponents(url:base.appendingPathComponent(clean),resolvingAgainstBaseURL:false) else{throw LaneAPIError.invalidURL}; if !query.isEmpty{c.queryItems=query}; guard let url=c.url else{throw LaneAPIError.invalidURL}
  var r=URLRequest(url:url);r.httpMethod=method;r.timeoutInterval=25;r.setValue("application/json",forHTTPHeaderField:"Accept");if let token,!token.isEmpty{r.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")};if let json{r.setValue("application/json",forHTTPHeaderField:"Content-Type");r.httpBody=try JSONSerialization.data(withJSONObject:json)};return r
 }
 func request(path:String,method:String="GET",token:String?=nil,query:[URLQueryItem]=[],json:[String:Any]?=nil,rawJSON:Any?=nil) async throws -> APIResult {
  var r=try build(path:path,method:method,token:token,query:query,json:json); if let rawJSON { r.setValue("application/json",forHTTPHeaderField:"Content-Type"); r.httpBody=try JSONSerialization.data(withJSONObject:rawJSON) };let(data,response)=try await URLSession.shared.data(for:r);guard let h=response as? HTTPURLResponse else{throw LaneAPIError.nonHTTP};return .init(status:h.statusCode,headers:h.allHeaderFields,data:data)
 }
 private func decoded<T:Decodable>(_ type:T.Type,path:String,method:String="GET",token:String?=nil,query:[URLQueryItem]=[],json:[String:Any]?=nil) async throws -> T {
  let r=try await request(path:path,method:method,token:token,query:query,json:json);guard (200..<300).contains(r.status) else{throw LaneAPIError.http(r.status,r.pretty)};do{return try JSONDecoder().decode(T.self,from:r.data)}catch{throw LaneAPIError.decoding(error.localizedDescription+"\n"+r.pretty)}
 }
 func pollAuth(authId:String, attempts:Int = 20) async throws -> LaneTokenResponse {
  let clean=authId.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty else{throw LaneAPIError.decoding("Empty auth id")};var lastStatus=0
  for index in 0..<attempts { let r=try await request(path:"/auth/\(clean)");lastStatus=r.status;if (200..<300).contains(r.status),!r.data.isEmpty{return try JSONDecoder().decode(LaneTokenResponse.self,from:r.data)};if index+1<attempts{try await Task.sleep(nanoseconds:3_000_000_000)}}
  throw LaneAPIError.http(lastStatus,"Authorization token was not returned after \(attempts) attempts")
 }
 func search(token:String,query:String,platform:String,version:String) async throws -> LaneCombinedSearchResponse {try await decoded(LaneCombinedSearchResponse.self,path:"/platforms/search",token:token,query:[.init(name:"q",value:query),.init(name:"platform",value:platform),.init(name:"ver",value:version)])}
 func stream(token:String,trackId:String,refId:String?,quality:String?) async throws -> TrackStreamingResult {try await decoded(TrackStreamingResult.self,path:"/track/stream",token:token,query:[.init(name:"trackId",value:trackId),.init(name:"refId",value:refId),.init(name:"streamQuality",value:quality)])}
 func trackStats(token:String,trackId:String) async throws -> TrackStatsDTO {try await decoded(TrackStatsDTO.self,path:"/track/stats",token:token,query:[.init(name:"trackId",value:trackId)])}
 func trackLyricsRaw(token:String,trackId:String) async throws -> APIResult {try await request(path:"/track/\(trackId)/lyrics",token:token)}
 func recommendationsRaw(token:String,trackId:String,platform:String) async throws -> APIResult {try await request(path:"/platforms/recommendations",token:token,query:[.init(name:"trackId",value:trackId),.init(name:"platform",value:platform)])}
 func searchHintsRaw(token:String,query:String) async throws -> APIResult {try await request(path:"/platforms/v2/hints",token:token,query:[.init(name:"q",value:query)])}
 func userPlaylistsRaw(token:String) async throws -> APIResult {try await request(path:"/user/playlists",token:token)}
 func recentRaw(token:String) async throws -> APIResult {try await request(path:"/user/recent",token:token)}
 func friendsRaw(token:String,page:Int=0,pageSize:Int=30,query:String="") async throws -> APIResult {try await request(path:"/user/friends",token:token,query:[.init(name:"page",value:String(page)),.init(name:"pageSize",value:String(pageSize)),.init(name:"q",value:query)])}
 func usersSearchRaw(token:String,query:String) async throws -> APIResult {try await request(path:"/users/search",token:token,query:[.init(name:"q",value:query)])}
 func notificationsRaw(token:String,page:Int=0,pageSize:Int=30,filter:String?=nil) async throws -> APIResult {try await request(path:"notifications",token:token,query:[.init(name:"page",value:String(page)),.init(name:"pageSize",value:String(pageSize)),.init(name:"filter",value:filter)])}
}