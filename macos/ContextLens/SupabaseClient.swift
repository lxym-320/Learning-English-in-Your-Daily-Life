import Foundation
import SwiftUI

struct CloudSession: Codable {
    let accessToken:String;let refreshToken:String;let userId:String;let email:String
}

@MainActor final class SupabaseClient:ObservableObject {
    static let shared=SupabaseClient()
    let base="https://zlybpcaeubirmcdtcuvg.supabase.co"
    let key="sb_publishable_E10YsdTduoIdJMpmQpqsHA_6pYjAHWE"
    @Published var session:CloudSession?;@Published var status="";@Published var busy=false
    private init(){if let data=UserDefaults.standard.data(forKey:"cloud.session"),let value=try? JSONDecoder().decode(CloudSession.self,from:data){session=value}}
    func headers(auth:Bool=true)->[String:String]{var h=["apikey":key,"Content-Type":"application/json"];if auth,let token=session?.accessToken{h["Authorization"]="Bearer \(token)"};return h}
    func request(path:String,method:String="GET",body:Any?=nil,auth:Bool=true,extra:[String:String]=[:])async throws->(Data,HTTPURLResponse){var req=URLRequest(url:URL(string:base+path)!);req.httpMethod=method;for(k,v)in headers(auth:auth).merging(extra,uniquingKeysWith:{$1}){req.setValue(v,forHTTPHeaderField:k)};if let body{req.httpBody=try JSONSerialization.data(withJSONObject:body)};req.timeoutInterval=30;let(data,response)=try await URLSession.shared.data(for:req);guard let http=response as? HTTPURLResponse else{throw URLError(.badServerResponse)};if http.statusCode>=400{let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any];let message=root?["msg"] as? String ?? root?["message"] as? String ?? root?["error_description"] as? String ?? "HTTP \(http.statusCode)";throw NSError(domain:"Supabase",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:message])};return(data,http)}
    func authenticate(email:String,password:String,signUp:Bool)async{busy=true;status="";defer{busy=false};do{let path=signUp ? "/auth/v1/signup":"/auth/v1/token?grant_type=password";let(data,_)=try await request(path:path,method:"POST",body:["email":email,"password":password],auth:false);let root=try JSONSerialization.jsonObject(with:data) as? [String:Any];guard let token=root?["access_token"] as? String,let refresh=root?["refresh_token"] as? String,let user=root?["user"] as? [String:Any],let id=user["id"] as? String else{status=signUp ? "注册成功，请先查收验证邮件，然后返回登录。":"登录响应不完整";return};let current=CloudSession(accessToken:token,refreshToken:refresh,userId:id,email:user["email"] as? String ?? email);session=current;UserDefaults.standard.set(try JSONEncoder().encode(current),forKey:"cloud.session");status="✓ 已登录，收藏和复习进度将自动同步。"}catch{status="登录失败：\(error.localizedDescription)"}}
    func signOut(){session=nil;UserDefaults.standard.removeObject(forKey:"cloud.session");status="已退出账户"}
    func push(_ item:SavedContext)async{guard let user=session?.userId else{return};let iso=ISO8601DateFormatter();let context:[String:Any]=["id":item.id.uuidString.lowercased(),"user_id":user,"sentence":item.sentence,"translation":item.translation,"next_review_at":iso.string(from:item.nextReview)];do{_=try await request(path:"/rest/v1/study_contexts?on_conflict=id",method:"POST",body:[context],extra:["Prefer":"resolution=merge-duplicates"]);let words=item.words.map{["id":$0.id.uuidString.lowercased(),"context_id":item.id.uuidString.lowercased(),"user_id":user,"word":$0.word,"meaning":$0.meaning,"review_hint":$0.hint,"phonetic":$0.phonetic,"meanings":$0.meanings,"next_review_at":iso.string(from:$0.nextReview)]};if !words.isEmpty{_=try await request(path:"/rest/v1/study_words?on_conflict=id",method:"POST",body:words,extra:["Prefer":"resolution=merge-duplicates"])};status="✓ 已同步"}catch{status="同步失败：\(error.localizedDescription)"}}
    func syncAll(_ items:[SavedContext])async{for item in items{await push(item)}}
}

struct AccountView:View {
    @ObservedObject var cloud=SupabaseClient.shared;let localItems:[SavedContext]
    @State var email="";@State var password="";@State var signUp=false
    var body:some View{VStack(alignment:.leading,spacing:18){Text("账户与同步").font(.title2.bold());if let session=cloud.session{Label(session.email,systemImage:"person.crop.circle.fill");Text("本机已有 \(localItems.count) 条收藏。登录后可同步到 Android。").foregroundStyle(.secondary);HStack{Button(cloud.busy ? "同步中…":"立即同步"){Task{cloud.busy=true;await cloud.syncAll(localItems);cloud.busy=false}}.disabled(cloud.busy);Button("退出登录",role:.destructive){cloud.signOut()}}}else{Picker("",selection:$signUp){Text("登录").tag(false);Text("注册").tag(true)}.pickerStyle(.segmented);TextField("邮箱",text:$email).textFieldStyle(.roundedBorder);SecureField("密码（至少 6 位）",text:$password).textFieldStyle(.roundedBorder);Button(cloud.busy ? "请稍候…":signUp ? "创建账户":"登录并同步"){Task{await cloud.authenticate(email:email.trimmingCharacters(in:.whitespacesAndNewlines),password:password,signUp:signUp)}}.buttonStyle(.borderedProminent).disabled(cloud.busy || !email.contains("@") || password.count<6)};if !cloud.status.isEmpty{Text(cloud.status).font(.caption).foregroundStyle(cloud.status.contains("失败") ? .red:.secondary).textSelection(.enabled)};Spacer()}.padding(28).frame(minWidth:430,minHeight:330)}
}
