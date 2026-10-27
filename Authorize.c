#include "Authorize.h"
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// One-shot authorization, no installed daemon or persistent authorization cache.
// Fixed executable inside the signed app; no shell command construction.
int authorized_reader(const char *helper,const char *operation,const char *owner,const char *restore,const char *expected,char **result) {
 *result=NULL;
 CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8*)helper,strlen(helper),false);
 SecStaticCodeRef code=NULL;SecRequirementRef requirement=NULL;
 OSStatus status=SecStaticCodeCreateWithPath(url,kSecCSDefaultFlags,&code);CFRelease(url);
 if(status==0)status=SecRequirementCreateWithString(CFSTR("anchor apple generic and identifier \"com.javierlozada.omnikeyhelper.configure\" and certificate leaf[subject.OU] = \"7NCA685F48\""),kSecCSDefaultFlags,&requirement);
 if(status==0)status=SecStaticCodeCheckValidity(code,kSecCSStrictValidate,requirement);
 if(requirement)CFRelease(requirement);if(code)CFRelease(code);if(status)return status;
 AuthorizationRef auth=NULL;status=AuthorizationCreate(NULL,kAuthorizationEmptyEnvironment,kAuthorizationFlagDefaults,&auth);if(status)return status;
 AuthorizationItem item={kAuthorizationRightExecute,0,NULL,0};
 AuthorizationRights rights={1,&item};
 status=AuthorizationCopyRights(auth,&rights,kAuthorizationEmptyEnvironment,kAuthorizationFlagInteractionAllowed|kAuthorizationFlagExtendRights,NULL);
 if(status){AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return status;}
 char *args[9]={(char*)operation,"--owner-uid",(char*)owner,NULL,NULL,NULL,NULL,NULL,NULL};int next=3;
 if(restore){args[next++]="--restore-file";args[next++]=(char*)restore;}
 if(expected){args[next++]="--expected-state";args[next++]=(char*)expected;}
 FILE *pipe=NULL;
 #pragma clang diagnostic push
 #pragma clang diagnostic ignored "-Wdeprecated-declarations"
 status=AuthorizationExecuteWithPrivileges(auth,helper,kAuthorizationFlagDefaults,args,&pipe);
 #pragma clang diagnostic pop
 if(status==0 && pipe){
  size_t count=0,capacity=65536;char *text=calloc(capacity,1);size_t n;
  if(!text){fclose(pipe);AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return -1;}
  while((n=fread(text+count,1,capacity-count-1,pipe))>0){count+=n;if(count==capacity-1){status=-1;break;}}
  text[count]=0;fclose(pipe);*result=text;
 }
 AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return status;
}
void free_authorized_result(char *result){free(result);}
