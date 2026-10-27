import Foundation
import Darwin
let nativeMode = CommandLine.arguments.contains("--native-apply") || CommandLine.arguments.contains("--native-inspect") || CommandLine.arguments.contains("--native-restore")
struct Failure: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ m:String){message=m} }
func require(_ condition:Bool,_ message:String) throws { if !condition { throw Failure(message) } }
func hex(_ b:[UInt8])->String { b.map{String(format:"%02X",$0)}.joined() }
func tlv(_ tag:UInt8,_ bytes:[UInt8])->[UInt8] { precondition(bytes.count<128); return [tag,UInt8(bytes.count)]+bytes }
func command(_ tags:[UInt8],_ data:[UInt8]=[])->[UInt8] {
 let payload=tags.reversed().reduce(data){tlv($1,$0)}
 return [0xff,0x70,0x07,0x6b,UInt8(payload.count)]+payload+[0]
}
func decode(_ response:[UInt8],tag:UInt8?,length:Int?=nil)throws->[UInt8] {
 try require(response.count>=4 && response.suffix(2)==[0x90,0],"Reader rejected command: \(hex(response))")
 let body=Array(response.dropLast(2))
 try require(body[0]==0xbd || (tag==nil && body[0]==0x9d),"Reader configuration error: \(hex(response))")
 try require(Int(body[1])+2==body.count,"Unexpected response length")
 if let tag {
  try require(body.count>=4 && body[2]==tag && Int(body[3])+4==body.count,"Unexpected configuration response")
  let data=Array(body.dropFirst(4)); if let length { try require(data.count==length,"Unexpected field length") }; return data
 }
 try require(body.count==2,"Unexpected write response"); return []
}
struct Slot:Codable,Equatable {
 let index:Int
 var fields:[[UInt8]]
 var cardType:UInt8 {fields[0][0]}
 var name:String { [0:"Unused",1:"MIFARE Classic",2:"Ultralight",3:"DESFire",4:"Seos",5:"iCLASS",6:"FeliCa",8:"ISO15693",9:"ISO14443B",10:"ISO14443A"][Int(cardType)] ?? "Type \(cardType)" }
 var suffix:[UInt8] { Array(fields[6].dropFirst(Int(fields[5][0])).prefix{ $0 != 0 }) }
 func validated() throws {
  try require((0..<3).contains(index) && fields.count==7,"Invalid backup slot")
  for i in 0..<7 {try require(fields[i].count==(i==6 ? 32:1),"Invalid configuration length")}
  try require(fields[5][0]<=32,"Unsupported post-stroke offset")
 }
}
struct Snapshot:Codable,Equatable {
 var schema=1
 let serial:String
 let product:String
 let slots:[Slot]
 func validated()throws {
  try require(schema==1 && !serial.isEmpty && product.contains("5027") && slots.map(\.index)==[0,1,2],"Backup is not a complete OmnikeyHelper 5027 snapshot")
  for s in slots {try s.validated()}
 }
 var summary:String {slots.map { s in
  let post=s.suffix.map{ $0==1 ? "Return" : ($0==9 ? "Tab" : "0x"+hex([$0])) }.joined(separator:" ")
  return "Slot \(s.index+1) · \(s.name) · After scan: \(post.isEmpty ? "nothing" : post)"
 }.joined(separator:"\n")}
}
func plan(_ old:Snapshot)throws->Snapshot {
 try old.validated(); var slots=old.slots
 let active=slots.filter{$0.cardType != 0}; try require(!active.isEmpty,"No active card types. Configure card reading before using OmnikeyHelper.")
 // Generic Type A may also match a more-specific Type A credential; refuse ambiguous output chains.
 if active.contains(where:{$0.cardType==10}) {
  try require(!active.contains(where:{[1,2,3,4].contains(Int($0.cardType))}),"Generic ISO14443A overlaps a specific card type. This configuration needs manual review to avoid adding two Returns.")
 }
 for s in active {
  let later=active.contains{$0.cardType==s.cardType && $0.index>s.index}
  if later {try require(!s.suffix.contains(1),"An earlier matching slot already presses Return. Review this multi-slot configuration manually."); continue}
  if s.suffix.last==1 {continue}
  try require(!s.suffix.contains(1),"An existing Return is followed by other keystrokes. Review this custom suffix manually.")
  var bytes=s.fields[6]; var start=Int(s.fields[5][0])
  if bytes.allSatisfy({$0==0}) {start=0;slots[s.index].fields[5]=[0]}
  let end=start+s.suffix.count
  try require(end<32,"Slot \(s.index+1) has no room for Return; existing strokes were preserved.")
  try require(bytes.dropFirst(end).allSatisfy{$0==0},"Slot \(s.index+1) has hidden custom strokes after a terminator. No changes made.")
  bytes[end]=1;slots[s.index].fields[6]=bytes
 }
 return Snapshot(serial:old.serial,product:old.product,slots:slots)
}
final class Reader {
 var opened=false
 func open()throws {if usb_capture()<0 {throw Failure(String(cString:usb_error()))};opened=true}
 func close(){if opened {usb_release();opened=false}}
 deinit {close()}
 func send(_ bytes:[UInt8])throws->[UInt8] {
  var out=[UInt8](repeating:0,count:512)
  let n = usb_exchange(bytes,Int32(bytes.count),&out,512)
  if n<0 {throw Failure(String(cString:usb_error()))};return Array(out.prefix(Int(n)))
 }
 func read()throws->Snapshot {
  let product=try decode(send(command([0xa2,0xa0,0xa0,0x82])),tag:0x82)
  let serial=try decode(send(command([0xa2,0xa0,0xa0,0x92])),tag:0x92)
  var slots=[Slot]()
  for i in 0..<3 { var fields=[[UInt8]](); for j in 0..<7 {
   fields.append(try decode(send(command([0xa2,0xa0,0xa4,UInt8(0xa8+i),UInt8(0x80+j)])),tag:UInt8(0x80+j),length:j==6 ? 32:1))
  };slots.append(Slot(index:i,fields:fields))}
  let result=Snapshot(serial:hex(serial),product:String(decoding:product.prefix{$0 != 0},as:UTF8.self),slots:slots)
  try result.validated();return result
 }
 func set(_ index:Int,_ field:Int,_ bytes:[UInt8])throws {
  _ = try decode(send(command([0xa2,0xa1,0xa4,UInt8(0xa8+index),UInt8(0x80+field)],bytes)),tag:nil)
 }
 func commit()throws { _ = try decode(send(command([0xa2,0xa1,0xa9,0x80])),tag:nil) }
}
let backupFolder:URL = {
 if nativeMode, let user=ProcessInfo.processInfo.environment["SUDO_USER"], let home=FileManager.default.homeDirectory(forUser:user) {return home.appendingPathComponent("Library/Application Support/OmnikeyHelper/Backups",isDirectory:true)}
 return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("OmnikeyHelper/Backups",isDirectory:true)
}()
func asBackupOwner<T>(_ operation:()throws->T)throws->T {
 if nativeMode && geteuid()==0 {
  guard let user=ProcessInfo.processInfo.environment["SUDO_USER"],let pw=getpwnam(user),pw.pointee.pw_uid>=501 else {throw Failure("Invalid backup owner")}
  let uid=pw.pointee.pw_uid,gid=pw.pointee.pw_gid
  try require(setegid(gid)==0,"Cannot set backup group")
  guard seteuid(uid)==0 else{setegid(0);throw Failure("Cannot set backup owner")}
  defer{seteuid(0);setegid(0)}
  return try operation()
 }
 return try operation()
}
func backup(_ state:Snapshot)throws->URL {
 return try asBackupOwner {
  try FileManager.default.createDirectory(at:backupFolder,withIntermediateDirectories:true)
  let url=backupFolder.appendingPathComponent("5027-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
  let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
  try encoder.encode(state).write(to:url,options:.atomic);return url
 }
}
func inspect()throws->Snapshot {let r=Reader();try r.open();defer{r.close()};return try r.read()}
func apply(expected:Snapshot,target:Snapshot,log:(String)->Void)throws {
 try target.validated()
 try require(target.serial==expected.serial && target.product==expected.product,"Backup belongs to another reader")
 for i in 0..<3 {try require(target.slots[i].fields.prefix(5)==expected.slots[i].fields.prefix(5),"Card/output settings differ from the backup. Restore refused to preserve those settings.")}
 let r=Reader();try r.open();defer{r.close()}
 let actual=try r.read();try require(actual==expected,"Reader or configuration changed. Inspect again before applying.")
 if actual==target {log("Return is already configured. No settings changed.");return}
 let url=try backup(actual);log("Backup saved: \(url.path)")
 let changes=(0..<3).flatMap{i in [5,6].filter{actual.slots[i].fields[$0] != target.slots[i].fields[$0]}.map{(i,$0)}}
 do {
  for (i,j) in changes {try r.set(i,j,target.slots[i].fields[j])}
  try require(try r.read()==target,"Staged settings did not match the requested change")
 } catch {
  let original=error
  do {for (i,j) in changes {try r.set(i,j,actual.slots[i].fields[j])};try require(try r.read()==actual,"Rollback verification failed")}
  catch {throw Failure("Change failed; rollback could not be verified. Backup: \(url.path). Reconnect and inspect before scanning. \(error.localizedDescription)")}
  throw original
 }
 // Apply resets the USB device. A transport error can mean it reset before replying.
 var commitError:String?
 do{try r.commit()}catch{commitError=error.localizedDescription}
 r.close(); Thread.sleep(forTimeInterval:1)
 do {
  try r.open();let saved=try r.read();try require(saved==target,"Saved settings differ from the requested configuration")
 } catch {throw Failure("Settings were sent, but persistence could not be verified. Reconnect and inspect before retrying. Backup: \(url.path). \(commitError ?? "") \(error.localizedDescription)")}
 log("Saved and read back successfully. Scan a card in the test box to confirm Return.")
}
