import SwiftUI
import AppKit
import ApplicationServices

struct LearnedWord: Codable, Identifiable, Hashable {
    var id:UUID;var word:String;var meaning:String;var hint:String;var phonetic:String;var meanings:[String];var nextReview:Date
    init(id:UUID=UUID(),word:String,meaning:String,hint:String,phonetic:String="",meanings:[String]=[],nextReview:Date=Date()){self.id=id;self.word=word;self.meaning=meaning;self.hint=hint;self.phonetic=phonetic;self.meanings=meanings.isEmpty ? [meaning]:meanings;self.nextReview=nextReview}
    enum CodingKeys:String,CodingKey{case id,word,meaning,hint,phonetic,meanings,nextReview}
    init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);id=try c.decodeIfPresent(UUID.self,forKey:.id) ?? UUID();word=try c.decode(String.self,forKey:.word);meaning=try c.decodeIfPresent(String.self,forKey:.meaning) ?? "";hint=try c.decodeIfPresent(String.self,forKey:.hint) ?? "";phonetic=try c.decodeIfPresent(String.self,forKey:.phonetic) ?? "";meanings=try c.decodeIfPresent([String].self,forKey:.meanings) ?? (meaning.isEmpty ? []:[meaning]);nextReview=try c.decodeIfPresent(Date.self,forKey:.nextReview) ?? Date.distantPast}
    func encode(to encoder:Encoder)throws{var c=encoder.container(keyedBy:CodingKeys.self);try c.encode(id,forKey:.id);try c.encode(word,forKey:.word);try c.encode(meaning,forKey:.meaning);try c.encode(hint,forKey:.hint);try c.encode(phonetic,forKey:.phonetic);try c.encode(meanings,forKey:.meanings);try c.encode(nextReview,forKey:.nextReview)}
}
struct SavedContext: Codable, Identifiable {
    var id = UUID(); var sentence: String; var translation: String; var words: [LearnedWord]; var createdAt = Date(); var nextReview = Date()
}
struct AIResult: Codable { var translation: String; var words: [LearnedWord] }

enum DeepSeekTransport {
    static let endpoints=["https://api.deepseek.com/v1/chat/completions","https://api.deepseek.com/chat/completions"]
    static func send(apiKey:String,payload:[String:Any]) async throws -> (Data,HTTPURLResponse) {
        let body=try JSONSerialization.data(withJSONObject:payload);var lastError:Error?
        for endpoint in endpoints {
            for attempt in 0..<2 {
                do {
                    var req=URLRequest(url:URL(string:endpoint)!);req.httpMethod="POST";req.setValue("Bearer \(apiKey)",forHTTPHeaderField:"Authorization");req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.setValue("ContextLens/1.1",forHTTPHeaderField:"User-Agent");req.timeoutInterval=35;req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData;req.httpBody=body
                    let config=URLSessionConfiguration.ephemeral;config.waitsForConnectivity=true;config.timeoutIntervalForRequest=35;config.timeoutIntervalForResource=45;config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData;config.connectionProxyDictionary=[:];config.httpShouldUsePipelining=false
                    let session=URLSession(configuration:config);let(data,response)=try await session.data(for:req);session.finishTasksAndInvalidate();guard let http=response as? HTTPURLResponse else{throw URLError(.badServerResponse)};return(data,http)
                } catch {lastError=error;if attempt==0{try? await Task.sleep(for:.milliseconds(700))}}
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }
}

@MainActor final class Store: ObservableObject {
    @Published var items: [SavedContext] = [] { didSet { save() } }
    @Published var lastResult: AIResult?; @Published var isLoading = false; @Published var error = ""
    init() { if let d=UserDefaults.standard.data(forKey:"contexts"),let v=try? JSONDecoder().decode([SavedContext].self,from:d){items=v} }
    func save(){if let d=try? JSONEncoder().encode(items){UserDefaults.standard.set(d,forKey:"contexts")}}
    func add(sentence:String,result:AIResult){let firstReview=Calendar.current.date(byAdding:.day,value:1,to:Date())!;let scheduled=result.words.map{var word=$0;word.nextReview=firstReview;return word};let item=SavedContext(sentence:sentence,translation:result.translation,words:scheduled,nextReview:firstReview);items.insert(item,at:0);Task{await SupabaseClient.shared.push(item)}}
    var due:[SavedContext]{items.filter{$0.nextReview <= Date()}}
    func rate(_ item:SavedContext,days:Int){guard let i=items.firstIndex(where:{$0.id==item.id}) else{return};items[i].nextReview=Calendar.current.date(byAdding:.day,value:days,to:Date())!;let changed=items[i];Task{await SupabaseClient.shared.push(changed)}}
    func rateWord(_ wordID:UUID,days:Int){for contextIndex in items.indices{if let wordIndex=items[contextIndex].words.firstIndex(where:{$0.id==wordID}){items[contextIndex].words[wordIndex].nextReview=Calendar.current.date(byAdding:.day,value:days,to:Date())!;items[contextIndex].nextReview=items[contextIndex].words.map(\.nextReview).min() ?? items[contextIndex].nextReview;let changed=items[contextIndex];Task{await SupabaseClient.shared.push(changed)};return}}}
}

enum Secret {
    static let key="deepseek.api.key"
    static func get()->String { UserDefaults.standard.string(forKey:key) ?? "" }
    static func set(_ value:String){UserDefaults.standard.set(value,forKey:key)}
}

@MainActor final class AIService {
    func analyze(_ text:String,store:Store) async {
        store.isLoading=true;store.error="";defer{store.isLoading=false};let key=Secret.get()
        guard !key.isEmpty else {store.lastResult=fallback(text);return}
        do {
            let prompt = "Translate the selected English into natural Chinese in context. Extract 1-4 genuinely useful English words or collocations, avoiding very basic words. For every word return: word, IPA phonetic, meaning in this sentence, meanings as an array of its common Chinese senses, and a memorable Chinese review hint. Return JSON only: {translation, words:[{word,phonetic,meaning,meanings,hint}]}. Text: \(text)"
            let payload: [String: Any] = ["model":"deepseek-chat", "messages":[["role":"system","content":"You are an English context-learning assistant. Always return valid JSON."],["role":"user","content":prompt]], "response_format":["type":"json_object"], "temperature":0.2]
            let(data,http)=try await DeepSeekTransport.send(apiKey:key,payload:payload);guard http.statusCode<300 else{let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any];let apiError=root?["error"] as? [String:Any];let message=apiError?["message"] as? String ?? String(data:data,encoding:.utf8) ?? "未知错误";throw NSError(domain:"DeepSeek",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:"DeepSeek \(http.statusCode)：\(message)"])}
            let root=try JSONSerialization.jsonObject(with:data) as? [String:Any];let choices=root?["choices"] as? [[String:Any]];let message=choices?.first?["message"] as? [String:Any];guard var json=message?["content"] as? String else{throw NSError(domain:"API",code:2,userInfo:[NSLocalizedDescriptionKey:"未能读取 DeepSeek 返回结果。"])};json=json.replacingOccurrences(of:"```json",with:"").replacingOccurrences(of:"```JSON",with:"").replacingOccurrences(of:"```",with:"").trimmingCharacters(in:.whitespacesAndNewlines);if let first=json.firstIndex(of:"{"),let last=json.lastIndex(of:"}"){json=String(json[first...last])};guard let object=try? JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any] else{throw NSError(domain:"API",code:3,userInfo:[NSLocalizedDescriptionKey:"DeepSeek 返回的内容不是有效 JSON：\(String(json.prefix(160)))"])};let result=(object["result"] as? [String:Any]) ?? object;let translation=(result["translation"] as? String) ?? (result["translated_text"] as? String) ?? (result["chinese"] as? String) ?? "";let rawWords=(result["words"] as? [[String:Any]]) ?? (result["vocabulary"] as? [[String:Any]]) ?? (result["terms"] as? [[String:Any]]) ?? [];let learned=rawWords.compactMap{item->LearnedWord? in let word=(item["word"] as? String) ?? (item["phrase"] as? String) ?? (item["term"] as? String) ?? "";guard !word.isEmpty else{return nil};let meaning=(item["meaning"] as? String) ?? (item["definition"] as? String) ?? (item["chinese"] as? String) ?? "结合原句理解";let hint=(item["hint"] as? String) ?? (item["review_hint"] as? String) ?? (item["tip"] as? String) ?? "回到原句主动回忆";let phonetic=(item["phonetic"] as? String) ?? (item["ipa"] as? String) ?? "";let meanings=(item["meanings"] as? [String]) ?? (item["definitions"] as? [String]) ?? [meaning];return LearnedWord(word:word,meaning:meaning,hint:hint,phonetic:phonetic,meanings:meanings)};guard !translation.isEmpty else{throw NSError(domain:"API",code:4,userInfo:[NSLocalizedDescriptionKey:"DeepSeek 已返回内容，但缺少 translation 字段：\(String(json.prefix(160)))"])};store.lastResult=AIResult(translation:translation,words:learned)
        }catch{store.error=error.localizedDescription;store.lastResult=fallback(text)}
    }
    func fallback(_ text:String)->AIResult {let tokens=text.lowercased().split(whereSeparator:{!$0.isLetter}).map(String.init);let strong=tokens.filter{$0.count>7}.prefix(3);return AIResult(translation:"演示分析：请在设置中填写 DeepSeek API 密钥，获得准确的语境翻译。",words:strong.map{LearnedWord(word:$0,meaning:"等待 AI 结合语境解释",hint:"回到原句，先猜它在这里表达什么。")})}
}

@MainActor final class SelectionMonitor: ObservableObject {
    var timer:Timer?;var globalMouseMonitor:Any?;var localMouseMonitor:Any?;var last="";var onSelection:((String,NSPoint)->Void)?;var onDeselection:(()->Void)?;var onGlobalMouseDown:(()->Void)?;var onLocalMouseDown:((NSEvent)->Void)?
    var lastDiagnostic="等待选中文字"
    var mouseDownPoint=NSPoint.zero;var selectionGesture=false;var mouseIsDown=false;var attemptID=0
    func start(){timer=Timer.scheduledTimer(withTimeInterval:0.55,repeats:true){[weak self]_ in Task { @MainActor in guard let self,!self.mouseIsDown else{return};_=self.readSelection() }};globalMouseMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]){[weak self] event in Task{@MainActor in self?.handleMouse(event)}};localMouseMonitor=NSEvent.addLocalMonitorForEvents(matching:.leftMouseDown){[weak self] event in self?.onLocalMouseDown?(event);return event}}
    func handleMouse(_ event:NSEvent){switch event.type{case .leftMouseDown:onGlobalMouseDown?();attemptID += 1;mouseIsDown=true;last="";mouseDownPoint=NSEvent.mouseLocation;selectionGesture=event.clickCount>=2;onDeselection?();case .leftMouseDragged:let point=NSEvent.mouseLocation;if hypot(point.x-mouseDownPoint.x,point.y-mouseDownPoint.y)>4{selectionGesture=true};case .leftMouseUp:mouseIsDown=false;let id=attemptID;selectionGesture=false;retrySelection(id:id,delays:[0.10,0.25,0.45]);default:break}}
    func retrySelection(id:Int,delays:[Double]){guard id==attemptID,let delay=delays.first else{if id==attemptID{last="";onDeselection?()};return};DispatchQueue.main.asyncAfter(deadline:.now()+delay){guard id==self.attemptID,!self.mouseIsDown else{return};if !self.readSelection(){self.retrySelection(id:id,delays:Array(delays.dropFirst()))}}}
    func accept(_ text:String)->Bool{let clean=text.trimmingCharacters(in:.whitespacesAndNewlines);guard clean.count>1,clean.count<1500 else{lastDiagnostic="选区为空或过长";return false};guard clean.range(of:"[A-Za-z]",options:.regularExpression) != nil else{lastDiagnostic="选区中没有英文";return false};lastDiagnostic="已读取：\(String(clean.prefix(40)))";if clean != last{last=clean;onSelection?(clean,NSEvent.mouseLocation)};return true}
    func readSelection()->Bool{guard AXIsProcessTrusted() else{lastDiagnostic="辅助功能权限未生效";return false};let system=AXUIElementCreateSystemWide();var focused:CFTypeRef?;if AXUIElementCopyAttributeValue(system,kAXFocusedUIElementAttribute as CFString,&focused) != .success || focused == nil{var app:CFTypeRef?;guard AXUIElementCopyAttributeValue(system,kAXFocusedApplicationAttribute as CFString,&app) == .success,let app else{lastDiagnostic="无法找到当前应用";return false};guard AXUIElementCopyAttributeValue(app as! AXUIElement,kAXFocusedUIElementAttribute as CFString,&focused) == .success,focused != nil else{lastDiagnostic="当前应用没有可读取的文本区域";return false}};let element=focused as! AXUIElement;var selected:CFTypeRef?;if AXUIElementCopyAttributeValue(element,kAXSelectedTextAttribute as CFString,&selected) == .success,let text=selected as? String,accept(text){return true};var range:CFTypeRef?;guard AXUIElementCopyAttributeValue(element,kAXSelectedTextRangeAttribute as CFString,&range) == .success,let range else{lastDiagnostic="当前应用未开放选中文本";return false};selected=nil;guard AXUIElementCopyParameterizedAttributeValue(element,kAXStringForRangeParameterizedAttribute as CFString,range,&selected) == .success,let text=selected as? String else{lastDiagnostic="无法读取所选文字";return false};return accept(text)}
}

final class FloatingPanel:NSPanel { override var canBecomeKey:Bool{true};init(rect:NSRect){super.init(contentRect:rect,styleMask:[.nonactivatingPanel,.borderless],backing:.buffered,defer:false);level = .floating;isOpaque=false;backgroundColor = .clear;hasShadow=true;collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]} }

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let store=Store(),monitor=SelectionMonitor(),ai=AIService();var buttonPanel:FloatingPanel?,detailWindow:NSWindow?,translationWindow:NSWindow?,selected="";var status:NSStatusItem?
    func applicationDidFinishLaunching(_ n:Notification){NSApp.setActivationPolicy(.accessory);status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);status?.button?.title="◉ Context";let menu=NSMenu();menu.addItem(withTitle:"账户与同步",action:#selector(openAccount),keyEquivalent:"");menu.addItem(withTitle:"复习与收藏",action:#selector(openLibrary),keyEquivalent:"");menu.addItem(withTitle:"设置 DeepSeek API",action:#selector(openSettings),keyEquivalent:"");menu.addItem(withTitle:"检查选词权限",action:#selector(checkPermission),keyEquivalent:"");menu.addItem(withTitle:"诊断当前选词",action:#selector(diagnoseSelection),keyEquivalent:"");menu.addItem(.separator());menu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");status?.menu=menu;monitor.onSelection={[weak self] text,point in self?.status?.button?.title="◉ Context ✓";self?.showButton(text,point)};monitor.onDeselection={[weak self] in self?.status?.button?.title=AXIsProcessTrusted() ? "◉ Context":"◉ Context ⚠︎";self?.hideButton()};monitor.start();let promptKey=kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String;let trusted=AXIsProcessTrustedWithOptions([promptKey:true] as CFDictionary);if !trusted{status?.button?.title="◉ Context ⚠︎"}else if Secret.get().isEmpty{DispatchQueue.main.async{self.openSettings()}}}
    func showButton(_ text:String,_ point:NSPoint){selected=text;buttonPanel?.close();let p=FloatingPanel(rect:NSRect(x:point.x+10,y:point.y-42,width:92,height:34));p.contentView=NSHostingView(rootView:QuickButton{[weak self] in self?.translate(text)});p.orderFrontRegardless();buttonPanel=p}
    func hideButton(){buttonPanel?.orderOut(nil);buttonPanel=nil;selected=""}
    func closeTranslationWindow(){translationWindow?.orderOut(nil);translationWindow=nil}
    func makeWindow(rect:NSRect,title:String,resizable:Bool=false)->NSWindow{var masks:NSWindow.StyleMask=[.titled,.closable,.miniaturizable];if resizable{masks.insert(.resizable)};let w=NSWindow(contentRect:rect,styleMask:masks,backing:.buffered,defer:false);w.title=title;w.isReleasedWhenClosed=false;return w}
    func translate(_ text:String){let clean=text.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty else{return};buttonPanel?.close();store.lastResult=nil;let p=makeWindow(rect:NSRect(x:max(20,NSEvent.mouseLocation.x-210),y:max(20,NSEvent.mouseLocation.y-540),width:430,height:520),title:"Context 翻译");p.delegate=self;p.contentView=NSHostingView(rootView:TranslationView(text:clean,store:store,service:ai));translationWindow=p;detailWindow=p;NSApp.activate(ignoringOtherApps:true);p.makeKeyAndOrderFront(nil);Task{await ai.analyze(clean,store:store)}}
    func windowDidResignKey(_ notification:Notification){guard let window=notification.object as? NSWindow,window === translationWindow else{return};closeTranslationWindow()}
    @objc func openLibrary(){let p=makeWindow(rect:NSRect(x:0,y:0,width:920,height:650),title:"Context · 学习中心",resizable:true);p.center();p.contentView=NSHostingView(rootView:LibraryView(store:store));detailWindow=p;NSApp.activate(ignoringOtherApps:true);p.makeKeyAndOrderFront(nil)}
    @objc func openAccount(){let p=makeWindow(rect:NSRect(x:0,y:0,width:480,height:390),title:"Context · 账户与同步");p.center();p.contentView=NSHostingView(rootView:AccountView(localItems:store.items));detailWindow=p;NSApp.activate(ignoringOtherApps:true);p.makeKeyAndOrderFront(nil)}
    @objc func openSettings(){let p=makeWindow(rect:NSRect(x:0,y:0,width:480,height:300),title:"Context · DeepSeek 设置");p.center();p.contentView=NSHostingView(rootView:SettingsView());detailWindow=p;NSApp.activate(ignoringOtherApps:true);p.makeKeyAndOrderFront(nil)}
    @objc func checkPermission(){if AXIsProcessTrusted(){status?.button?.title="◉ Context";let alert=NSAlert();alert.messageText="选词权限已开启";alert.informativeText="现在可在浏览器、PDF、Word 等应用中拖动或双击选中英文。";alert.runModal()}else{let alert=NSAlert();alert.messageText="新版需要重新授权选词权限";alert.informativeText="打开系统设置后，请在“辅助功能”中先关闭再重新开启 Context Lens；如果列表里有旧版，请删除旧项后添加当前应用。然后彻底退出并重新启动 Context Lens。";alert.addButton(withTitle:"打开系统设置");alert.addButton(withTitle:"稍后");if alert.runModal() == .alertFirstButtonReturn{NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}}}
    @objc func diagnoseSelection(){let success=monitor.readSelection();let alert=NSAlert();alert.messageText=success ? "选词读取正常":"选词读取失败";alert.informativeText=monitor.lastDiagnostic+(success ? "\n已在鼠标附近显示翻译按钮。":"\n请先在浏览器或文本编辑器中选中一段英文，再立即点击菜单栏 Context → 诊断当前选词。");alert.runModal()}
}

struct QuickButton:View {var action:()->Void;var body:some View{Button(action:action){HStack(spacing:7){Image(systemName:"translate");Text("翻译")}.font(.system(size:13,weight:.semibold)).padding(.horizontal,15).frame(height:32).background(Color(red:0.09,green:0.28,blue:0.23)).foregroundStyle(.white).clipShape(Capsule())}.buttonStyle(.plain)}}
struct TranslationView:View {
    let text:String
    @ObservedObject var store:Store
    let service:AIService
    @State private var saved=false
    @State private var selectedWordIDs:Set<UUID>=[]
    var body:some View {
        VStack(alignment:.leading,spacing:15) {
            Text("CONTEXT TRANSLATION").font(.caption2.bold()).tracking(1.4).foregroundStyle(.secondary)
            ScrollView {
                Text(text).font(.system(size:17,design:.serif)).frame(maxWidth:.infinity,alignment:.leading)
                Divider().padding(.vertical,5)
                if store.isLoading {
                    ProgressView("正在结合上下文分析…").frame(maxWidth:.infinity).padding(28)
                } else if let result=store.lastResult {
                    if !store.error.isEmpty { Text(store.error).font(.caption).foregroundStyle(.red).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:8)) }
                    Text(result.translation).font(.system(size:15,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading)
                    if !result.words.isEmpty {
                        HStack {
                            Text("选择想收藏的好词").font(.caption.bold()).foregroundStyle(.secondary)
                            Spacer()
                            Button("全选"){selectedWordIDs=Set(result.words.map(\.id))}.buttonStyle(.plain).font(.caption)
                            Text("·").foregroundStyle(.tertiary)
                            Button("清空"){selectedWordIDs.removeAll()}.buttonStyle(.plain).font(.caption)
                        }.padding(.top,8)
                        ForEach(result.words) { word in
                            Button {
                                if selectedWordIDs.contains(word.id){selectedWordIDs.remove(word.id)}else{selectedWordIDs.insert(word.id)}
                            } label: {
                                HStack(alignment:.top,spacing:10) {
                                    Image(systemName:selectedWordIDs.contains(word.id) ? "checkmark.square.fill":"square").font(.system(size:17)).foregroundStyle(selectedWordIDs.contains(word.id) ? Color(red:0.09,green:0.28,blue:0.23):Color.secondary)
                                    VStack(alignment:.leading,spacing:4) { HStack(spacing:7){Text(word.word).bold();if !word.phonetic.isEmpty{Text(word.phonetic).font(.caption).foregroundStyle(.secondary)}};Text(word.meaning);Text("复习提示："+word.hint).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                }.padding(10).contentShape(Rectangle()).background(selectedWordIDs.contains(word.id) ? Color.green.opacity(0.12):Color.gray.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:9))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
            Button(saved ? "✓ 已收藏 \(selectedWordIDs.count) 个词" : "收藏已选的 \(selectedWordIDs.count) 个词") {
                if let result=store.lastResult {let chosen=result.words.filter{selectedWordIDs.contains($0.id)};guard !chosen.isEmpty else{return};store.add(sentence:text,result:AIResult(translation:result.translation,words:chosen));saved=true}
            }.buttonStyle(.borderedProminent).tint(Color(red:0.09,green:0.28,blue:0.23)).frame(maxWidth:.infinity).disabled(selectedWordIDs.isEmpty || saved)
        }.padding(22)
    }
}
struct ReviewEntry:Identifiable,Hashable {
    let id:UUID;let contextID:UUID;let word:LearnedWord;let sentence:String;let translation:String;let nextReview:Date
}
enum LibrarySection:String,CaseIterable,Identifiable {case overview="学习概览";case dictionary="单词字典";case review="复习训练";var id:String{rawValue}}
enum ReviewMode:String,CaseIterable,Identifiable {case englishToChinese="看英文 · 回答中文";case chineseToEnglish="看中文 · 回答英文";var id:String{rawValue}}
struct LibraryView:View {
    @ObservedObject var store:Store
    @State private var section:LibrarySection = .overview
    var entries:[ReviewEntry]{store.items.flatMap{item in item.words.map{ReviewEntry(id:$0.id,contextID:item.id,word:$0,sentence:item.sentence,translation:item.translation,nextReview:$0.nextReview)}}}
    var body:some View {
        NavigationSplitView {
            List(selection:$section){Label("学习概览",systemImage:"chart.bar").tag(LibrarySection.overview);Label("单词字典",systemImage:"character.book.closed").tag(LibrarySection.dictionary);Label("复习训练",systemImage:"rectangle.stack.badge.play").tag(LibrarySection.review)}.navigationTitle("学习中心").frame(minWidth:170)
        } detail: {
            switch section {case .overview:LearningOverviewView(entries:entries,startReview:{section = .review});case .dictionary:DictionaryView(entries:entries);case .review:ReviewPracticeView(store:store,entries:entries)}
        }
    }
}
struct LearningOverviewView:View {
    let entries:[ReviewEntry];let startReview:()->Void
    var dueCount:Int{entries.filter{$0.nextReview <= Date()}.count}
    var scheduledCount:Int{max(entries.count-dueCount,0)}
    var body:some View{ScrollView{VStack(alignment:.leading,spacing:24){VStack(alignment:.leading,spacing:6){Text("今天继续一点点").font(.largeTitle.bold());Text("从真实语境收藏，在恰当时间重新想起。").foregroundStyle(.secondary)};HStack(spacing:14){MetricCard(title:"词库",value:"\(entries.count)",caption:"已收藏单词",icon:"character.book.closed");MetricCard(title:"今日",value:"\(dueCount)",caption:"待复习",icon:"clock");MetricCard(title:"计划中",value:"\(scheduledCount)",caption:"后续复习",icon:"calendar")};GroupBox{VStack(alignment:.leading,spacing:12){Label(dueCount == 0 ? "今天已完成":"今天还有 \(dueCount) 个单词",systemImage:dueCount == 0 ? "checkmark.circle.fill":"rectangle.stack.badge.play").font(.title3.bold()).foregroundStyle(dueCount == 0 ? .green:.primary);Text(dueCount == 0 ? "保持轻量、持续的学习节奏，比一次记很多更有效。":"每个词独立安排复习，答完后会自动进入下一词。").foregroundStyle(.secondary);Button("开始今日复习",action:startReview).buttonStyle(.borderedProminent).controlSize(.large).disabled(dueCount==0)}.frame(maxWidth:.infinity,alignment:.leading).padding(10)};Text("建议流程：阅读时选词 → 查看语境翻译 → 只收藏真正想学的词 → 每天完成待复习。 ").font(.callout).foregroundStyle(.secondary)}.padding(32).frame(maxWidth:850,alignment:.leading)}}
}
struct MetricCard:View {let title:String;let value:String;let caption:String;let icon:String;var body:some View{VStack(alignment:.leading,spacing:7){Label(title,systemImage:icon).foregroundStyle(.secondary);Text(value).font(.system(size:30,weight:.bold,design:.rounded));Text(caption).font(.caption).foregroundStyle(.secondary)}.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius:14))}}
struct DictionaryView:View {
    let entries:[ReviewEntry]
    @State private var query="";@State private var selection:UUID?
    var filtered:[ReviewEntry]{let q=query.trimmingCharacters(in:.whitespacesAndNewlines).lowercased();guard !q.isEmpty else{return entries};return entries.filter{entry in ([entry.word.word,entry.word.phonetic,entry.word.meaning,entry.sentence]+entry.word.meanings).joined(separator:" ").lowercased().contains(q)}}
    var selectedEntry:ReviewEntry?{filtered.first(where:{$0.id==selection}) ?? filtered.first}
    var body:some View {HSplitView {List(filtered,selection:$selection){entry in WordRow(entry:entry).tag(entry.id)}.searchable(text:$query,prompt:"搜索单词、释义或原句").frame(minWidth:240,idealWidth:280);Group{if let entry=selectedEntry{WordDetailView(entry:entry)}else{ContentUnavailableView(query.isEmpty ? "还没有收藏单词":"没有找到单词",systemImage:"text.book.closed",description:Text(query.isEmpty ? "翻译后选择想学习的词并收藏。":"试试其他单词或释义。"))}}.frame(minWidth:380,maxWidth:.infinity,maxHeight:.infinity)}.navigationTitle("单词字典")}
}
struct WordDetailView:View {
    let entry:ReviewEntry
    var body:some View{ScrollView{VStack(alignment:.leading,spacing:18){VStack(alignment:.leading,spacing:5){Text(entry.word.word).font(.system(size:36,weight:.bold,design:.rounded)).textSelection(.enabled);if !entry.word.phonetic.isEmpty{Text(entry.word.phonetic).font(.title3).foregroundStyle(.secondary).textSelection(.enabled)}};GroupBox("常见释义"){VStack(alignment:.leading,spacing:8){ForEach(Array(entry.word.meanings.enumerated()),id:\.offset){index,value in Text("\(index + 1). \(value)").frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}}.padding(.vertical,4)};GroupBox("收藏时的语境"){VStack(alignment:.leading,spacing:9){Text(entry.word.meaning).fontWeight(.medium);Divider();Text(entry.sentence).italic().textSelection(.enabled);Text(entry.translation).foregroundStyle(.secondary).textSelection(.enabled)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,4)};if !entry.word.hint.isEmpty{Label(entry.word.hint,systemImage:"lightbulb").foregroundStyle(.secondary)};Label(entry.nextReview <= Date() ? "现在需要复习":"已安排后续复习",systemImage:entry.nextReview <= Date() ? "clock.badge.exclamationmark":"calendar.badge.checkmark").font(.caption).foregroundStyle(.secondary)}.padding(30).frame(maxWidth:.infinity,alignment:.leading)}}
}
struct ReviewPracticeView:View {
    @ObservedObject var store:Store;let entries:[ReviewEntry]
    @State private var mode:ReviewMode = .englishToChinese;@State private var sessionIDs:[UUID]=[];@State private var currentIndex=0;@State private var revealed=false;@State private var answer="";@State private var started=false
    var due:[ReviewEntry]{entries.filter{$0.nextReview <= Date()}}
    var current:ReviewEntry?{guard currentIndex<sessionIDs.count else{return nil};return entries.first(where:{$0.id==sessionIDs[currentIndex]})}
    var body:some View{VStack(spacing:0){HStack{VStack(alignment:.leading,spacing:3){Text("复习训练").font(.title2.bold());Text("今日待复习 \(due.count) 个单词").foregroundStyle(.secondary)};Spacer();Picker("复习方式",selection:$mode){ForEach(ReviewMode.allCases){Text($0.rawValue).tag($0)}}.frame(width:230).onChange(of:mode){revealed=false;answer=""}}.padding(24);Divider();reviewContent}.navigationTitle("复习训练")}
    @ViewBuilder var reviewContent:some View {if !started{VStack(spacing:18){Image(systemName:"rectangle.stack.badge.play").font(.system(size:52)).foregroundStyle(.secondary);Text(due.isEmpty ? "今天的复习已完成":"准备好开始了吗？").font(.title2.bold());Text(due.isEmpty ? "新的单词会按照复习计划自动出现。":"选择复习方式，然后依次完成今天的单词。").foregroundStyle(.secondary);Button("开始复习"){sessionIDs=due.map(\.id);currentIndex=0;revealed=false;answer="";started=true}.buttonStyle(.borderedProminent).controlSize(.large).disabled(due.isEmpty)}.frame(maxWidth:.infinity,maxHeight:.infinity)}else if let entry=current{VStack(spacing:22){HStack{Text("\(currentIndex + 1) / \(sessionIDs.count)").font(.caption.bold()).foregroundStyle(.secondary);ProgressView(value:Double(currentIndex),total:Double(max(sessionIDs.count,1))).frame(maxWidth:260)};Spacer();question(entry);TextField(mode == .englishToChinese ? "输入中文意思（可选）":"输入英文单词（可选）",text:$answer).textFieldStyle(.roundedBorder).frame(maxWidth:380).onSubmit{revealed=true};if revealed{answerView(entry)};Spacer();if revealed{HStack(spacing:12){Button("没记住"){grade(days:0)}.tint(.red);Button("有点模糊"){grade(days:1)}.tint(.orange);Button("记住了"){grade(days:4)}.tint(.green)}.buttonStyle(.borderedProminent).controlSize(.large)}else{Button("显示答案"){revealed=true}.buttonStyle(.borderedProminent).controlSize(.large)}}.padding(30).frame(maxWidth:.infinity,maxHeight:.infinity)}else{VStack(spacing:16){Image(systemName:"checkmark.circle.fill").font(.system(size:58)).foregroundStyle(.green);Text("本轮复习完成").font(.title.bold());Text("已完成 \(sessionIDs.count) 个单词").foregroundStyle(.secondary);Button("返回"){started=false;sessionIDs=[];currentIndex=0}.buttonStyle(.borderedProminent)}.frame(maxWidth:.infinity,maxHeight:.infinity)}}
    @ViewBuilder func question(_ entry:ReviewEntry)->some View{VStack(spacing:12){if mode == .englishToChinese{Text(entry.word.word).font(.system(size:42,weight:.bold,design:.rounded));if !entry.word.phonetic.isEmpty{Text(entry.word.phonetic).font(.title3).foregroundStyle(.secondary)};Text("请回忆它的中文意思").foregroundStyle(.secondary)}else{Text(entry.word.meanings.first ?? entry.word.meaning).font(.system(size:30,weight:.semibold)).multilineTextAlignment(.center);Text("请说出或写出对应的英文").foregroundStyle(.secondary)}}}
    @ViewBuilder func answerView(_ entry:ReviewEntry)->some View{VStack(spacing:9){Divider();if mode == .englishToChinese{ForEach(entry.word.meanings,id:\.self){Text($0).font(.title3)}}else{Text(entry.word.word).font(.system(size:34,weight:.bold));if !entry.word.phonetic.isEmpty{Text(entry.word.phonetic).foregroundStyle(.secondary)}};Text(entry.sentence).italic().foregroundStyle(.secondary).padding(.top,5)}.frame(maxWidth:520)}
    func grade(days:Int){guard let entry=current else{return};store.rateWord(entry.id,days:days);currentIndex += 1;revealed=false;answer=""}
}
struct WordRow:View {
    let entry:ReviewEntry
    var body:some View{VStack(alignment:.leading,spacing:3){Text(entry.word.word).fontWeight(.semibold);HStack(spacing:6){if !entry.word.phonetic.isEmpty{Text(entry.word.phonetic)};Text(entry.word.meanings.first ?? entry.word.meaning).lineLimit(1)}}.font(.callout).foregroundStyle(.primary).padding(.vertical,3)}
}
struct SettingsView:View {
    @State var key=Secret.get();@State var done=false;@State var testing=false;@State var testResult=""
    var body:some View {
        Form {
            Section("DeepSeek AI 语境分析") { HStack{SecureField("粘贴 sk- 开头的 DeepSeek API 密钥",text:$key).textFieldStyle(.roundedBorder);Button("粘贴"){key=NSPasteboard.general.string(forType:.string) ?? ""}};Text("密钥仅保存在本机应用设置中，不再访问系统钥匙串，因此不会反复要求登录密码。").font(.caption).foregroundStyle(.secondary);HStack{Button(done ? "✓ 已保存" : "保存 DeepSeek 密钥"){Secret.set(key.trimmingCharacters(in:.whitespacesAndNewlines));done=true}.disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty);Button(testing ? "正在测试…" : "测试 DeepSeek 连接"){let clean=key.trimmingCharacters(in:.whitespacesAndNewlines);Secret.set(clean);testing=true;testResult="";Task{testResult=await testConnection(clean);testing=false}}.disabled(testing || key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)};if !testResult.isEmpty{Text(testResult).font(.caption).foregroundStyle(testResult.hasPrefix("✓") ? .green:.red).textSelection(.enabled)} }
            Section("系统权限") { Text("请在 系统设置 → 隐私与安全性 → 辅助功能 中允许 Context Lens，应用才能读取其他应用的选中文本。") }
        }.formStyle(.grouped).padding(8)
    }
    func testConnection(_ apiKey:String) async->String{do{let payload:[String:Any]=["model":"deepseek-chat","messages":[["role":"user","content":"Reply with OK only"]],"max_tokens":8];let(data,http)=try await DeepSeekTransport.send(apiKey:apiKey,payload:payload);if http.statusCode<300{return "✓ DeepSeek 连接成功，可以开始翻译。"};let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any];let error=root?["error"] as? [String:Any];return "✗ DeepSeek \(http.statusCode)：\(error?["message"] as? String ?? String(data:data,encoding:.utf8) ?? "未知错误")"}catch{let ns=error as NSError;return "✗ 网络错误 \(ns.code)：\(error.localizedDescription)。已尝试直连、备用地址和自动重试。"}}
}

@main struct ContextLensApp:App {@NSApplicationDelegateAdaptor(AppDelegate.self)var delegate;var body:some Scene{Settings{EmptyView()}}}
