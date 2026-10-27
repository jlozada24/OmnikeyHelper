import Foundation
import Darwin
@main struct NativeConfigure {
 static func main() {
  // Diagnostics and protocol result share the authorization pipe.
  dup2(STDOUT_FILENO,STDERR_FILENO)
  do {
   try require(nativeMode && geteuid()==0,"Administrator authorization is required.")
   let args=CommandLine.arguments
   if let pos=args.firstIndex(of:"--owner-uid"),pos+1<args.count,let uid=UInt32(args[pos+1]),uid>=501,let pw=getpwuid(uid) {
    setenv("SUDO_USER",pw.pointee.pw_name,1)
   }
   try require(ProcessInfo.processInfo.environment["SUDO_USER"] != nil,"Cannot determine the backup owner.")
   let current=try inspect();print(current.product);print(current.summary)
   if let p=args.firstIndex(of:"--expected-state"),p+1<args.count {
    guard let data=Data(base64Encoded:args[p+1]) else{throw Failure("Invalid expected settings")}
    try require(try JSONDecoder().decode(Snapshot.self,from:data)==current,"Reader or settings changed. Inspect again before applying.")
   }
   var final=current
   if args.contains("--native-apply") {final=try plan(current);try apply(expected:current,target:final,log:{print($0);fflush(stdout)})}
   if args.contains("--native-restore") {
    guard let p=args.firstIndex(of:"--restore-file"),p+1<args.count else{throw Failure("Choose a backup to restore.")}
    let data=try asBackupOwner{try Data(contentsOf:URL(fileURLWithPath:args[p+1]))}
    final=try JSONDecoder().decode(Snapshot.self,from:data)
    try apply(expected:current,target:final,log:{print($0);fflush(stdout)})
   }
   print("OMNIKEY_RESULT:"+(try JSONEncoder().encode(final)).base64EncodedString())
  } catch {print("ERROR: "+error.localizedDescription);exit(1)}
 }
}
