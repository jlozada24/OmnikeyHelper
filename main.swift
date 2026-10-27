import AppKit
import UniformTypeIdentifiers

func selfTest()throws {
 func snapshot(_ bytes:[UInt8]=[UInt8](repeating:0,count:32),_ offset:UInt8=0)->Snapshot {
  Snapshot(serial:"TEST",product:"OMNIKEY 5027",slots:(0..<3).map{i in Slot(index:i,fields:[[i==0 ? 1:0],[3],[0],[0],[4],[offset],bytes])})
 }
 let original=snapshot();let planned=try plan(original)
 try require(planned.slots[0].fields[6][0]==1,"Empty suffix test")
 try require(try plan(planned)==planned,"Idempotence test")
 try require(planned.slots[1]==original.slots[1],"Inactive slot preservation")
 var strokes=[UInt8](repeating:0,count:32);strokes[0]=65;strokes[1]=9
 let custom=try plan(snapshot(strokes,1));try require(custom.slots[0].fields[6].prefix(3)==[65,9,1],"Prefix/suffix preservation")
 do {_ = try plan(snapshot([UInt8](repeating:65,count:32)));throw Failure("Full buffer was accepted")}catch let e as Failure {try require(e.message.contains("no room"),"Full buffer rejection")}
 try require(hex(command([0xa2,0xa0,0xa4,0xa8,0x85]))=="FF70076B0AA208A006A404A802850000","HID GET fixture")
 try require(hex(command([0xa2,0xa1,0xa4,0xa8,0x85],[0]))=="FF70076B0BA209A107A405A80385010000","HID SET fixture")
 try require(try decode([0xbd,3,0x85,1,0,0x90,0],tag:0x85,length:1)==[0],"Response decode")
 for bad:[UInt8] in [[],[0x9e,2,0,0x31,0x90,0],[0xbd,3,0x85,1,0,0x6a,0x80],[0xbd,3,0x86,1,0,0x90,0]] {
  do {_ = try decode(bad,tag:0x85,length:1);throw Failure("Invalid response accepted")}catch let e as Failure {try require(e.message != "Invalid response accepted","Invalid response accepted")}
 }
 print("PASS: protocol fixtures, response rejection, suffix preservation, idempotence, inactive slots and full-buffer handling")
}
if CommandLine.arguments.contains("--self-test") {
 do{try selfTest();exit(0)}catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}
if CommandLine.arguments.contains("--inspect") || CommandLine.arguments.contains("--apply") {
 do {
  let current=try inspect();print(current.product);print(current.summary)
  if CommandLine.arguments.contains("--apply") {try apply(expected:current,target:plan(current),log:{print($0)})}
  exit(0)
 }catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}
final class Controller:NSObject,NSApplicationDelegate {
 var window:NSWindow!
 let status=NSTextField(wrappingLabelWithString:"Connect one OMNIKEY 5027, remove any card, then inspect its settings.")
 let details=NSTextField(wrappingLabelWithString:"Your reader’s settings will appear here.")
 let result=NSTextField(wrappingLabelWithString:"The test box clears after Return. Card numbers are not saved.")
 let test=NSTextField()
 let logView=NSTextView()
 var inspectButton:NSButton!;var applyButton:NSButton!;var restoreButton:NSButton!
 var state:Snapshot?;var proposed:Snapshot?;var busy=false
 func label(_ text:String,_ size:CGFloat,_ bold:Bool=false)->NSTextField {let t=NSTextField(wrappingLabelWithString:text);t.font=bold ? .boldSystemFont(ofSize:size):.systemFont(ofSize:size);return t}
 func applicationDidFinishLaunching(_ notification:Notification) {
  let appMenu=NSMenu();let top=NSMenuItem();appMenu.addItem(top);let submenu=NSMenu();submenu.addItem(withTitle:"Quit OmnikeyHelper",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");top.submenu=submenu;NSApp.mainMenu=appMenu
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.title="OmnikeyHelper";window.minSize=NSSize(width:640,height:640)
  let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false
  window.contentView!.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:28),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-24)])
  stack.addArrangedSubview(label("Scan. Return. Done.",28,true))
  stack.addArrangedSubview(label("Add an automatic Return to your OMNIKEY 5027.",14))
  status.font = .systemFont(ofSize:13);stack.addArrangedSubview(status)
  let buttons=NSStackView();buttons.orientation = .horizontal;buttons.spacing=10
  inspectButton=NSButton(title:"1. Inspect Reader",target:self,action:#selector(inspectClick));applyButton=NSButton(title:"2. Add Return",target:self,action:#selector(applyClick));restoreButton=NSButton(title:"Restore Backup…",target:self,action:#selector(restoreClick))
  for b in [inspectButton!,applyButton!,restoreButton!] {b.bezelStyle = .rounded;buttons.addArrangedSubview(b)}
  applyButton.isEnabled=false;restoreButton.isEnabled=false;stack.addArrangedSubview(buttons)
  details.font = .monospacedSystemFont(ofSize:12,weight:.regular);stack.addArrangedSubview(details)
  stack.addArrangedSubview(label("Test a scan",16,true))
  test.placeholderString="Click here, then scan a card";test.font = .monospacedSystemFont(ofSize:16,weight:.regular);test.target=self;test.action=#selector(returnReceived)
  stack.addArrangedSubview(test);test.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
  result.font = .systemFont(ofSize:12);result.textColor = .secondaryLabelColor;stack.addArrangedSubview(result)
  let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;scroll.documentView=logView;logView.isEditable=false;logView.isSelectable=true;logView.font = .monospacedSystemFont(ofSize:11,weight:.regular);logView.autoresizingMask=[.width];logView.textContainer?.widthTracksTextView=true
  stack.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:110).isActive=true
  for view in stack.arrangedSubviews where view is NSTextField { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true }
  window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  if busy {status.stringValue="Please wait for the reader operation to finish before quitting.";return .terminateCancel};return .terminateNow
 }
 func log(_ message:String){logView.string += message+"\n";logView.scrollToEndOfDocument(nil)}
 func run(_ work:@escaping ()throws->Snapshot?) {
  busy=true;inspectButton.isEnabled=false;applyButton.isEnabled=false;restoreButton.isEnabled=false;status.stringValue="Working with the reader… Please leave it connected."
  DispatchQueue.global(qos:.userInitiated).async {
   var next:Snapshot?;var issue:String?
   do{next=try work()}catch{issue=error.localizedDescription}
   DispatchQueue.main.async {
    self.busy=false;self.inspectButton.isEnabled=true;self.state=next;self.proposed=nil
    if let issue {self.status.stringValue="Operation needs attention";self.log(issue)}
    else if let next {
     self.details.stringValue=next.summary;self.restoreButton.isEnabled=true
     do {self.proposed=try plan(next);self.applyButton.isEnabled=self.proposed != next;self.status.stringValue=self.proposed==next ? "Return is configured. Test a scan below." : "Ready. Add Return will back up and update the active card settings."}
     catch {self.status.stringValue="Custom settings need review";self.log(error.localizedDescription)}
    }
   }
  }
 }
 @objc func inspectClick(){run{try inspect()}}
 @objc func applyClick(){guard let old=state,let target=proposed else{return};run {try apply(expected:old,target:target,log:{m in DispatchQueue.main.async{self.log(m)}});return try inspect()}}
 @objc func restoreClick(){guard let old=state else{return};let panel=NSOpenPanel();panel.title="Select an OmnikeyHelper backup for this reader";panel.allowedContentTypes=[.json];panel.directoryURL=backupFolder
  if panel.runModal() == .OK,let url=panel.url {run {let target=try JSONDecoder().decode(Snapshot.self,from:Data(contentsOf:url));try apply(expected:old,target:target,log:{m in DispatchQueue.main.async{self.log(m)}});return try inspect()}}
 }
 @objc func returnReceived(){if !test.stringValue.isEmpty {result.stringValue="Return received ✓ — scan submitted and cleared.";result.textColor = .systemGreen;test.stringValue=""}}
}
let application=NSApplication.shared
let controller=Controller();application.delegate=controller;application.setActivationPolicy(.regular);application.run()
