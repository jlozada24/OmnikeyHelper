#include "Reader.h"
#include "Features.h"
#include <PCSC/winscard.h>
#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
static SCARDCONTEXT context;
static SCARDHANDLE card;
static uint32_t protocol;
static int directMode;
static uint32_t escapeCode;
static char errorText[512];
const char *reader_error(void) { return errorText; }
static int fail(const char *operation, long code) {
 const char *advice = ((code & 0xffffffffUL)==0xe00002e2UL)
  ? "Allow OmnikeyHelper in Privacy & Security > Input Monitoring, then quit and reopen it."
  : "Close other reader software, reconnect the reader, and inspect again. This is a reader/PCSC error, not an Input Monitoring permission error.";
 snprintf(errorText,sizeof(errorText),"%s (0x%08lx). %s",operation,code & 0xffffffffUL,advice); return -1;
}
// Enumerate only the exact OMNIKEY 5027 USB IDs. Never capture input events.
static int switchMode(int enable) {
 IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
 int vendor=0x076b;
 CFNumberRef vn=CFNumberCreate(NULL,kCFNumberIntType,&vendor);
 const void *keys[]={CFSTR(kIOHIDVendorIDKey)}; const void *values[]={vn};
 CFDictionaryRef match=CFDictionaryCreate(NULL,keys,values,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 IOHIDManagerSetDeviceMatching(manager,match); CFRelease(match); CFRelease(vn);
 CFSetRef devices=IOHIDManagerCopyDevices(manager);
 IOHIDDeviceRef chosen=NULL; int count=0,pid=0;
 if(devices) {
  CFIndex n=CFSetGetCount(devices); const void **items=calloc(n,sizeof(void*)); CFSetGetValues(devices,items);
  for(CFIndex i=0;i<n;i++) {
   IOHIDDeviceRef d=(IOHIDDeviceRef)items[i]; int product=0;
   CFTypeRef p=IOHIDDeviceGetProperty(d,CFSTR(kIOHIDProductIDKey));
   if(p && CFGetTypeID(p)==CFNumberGetTypeID()) CFNumberGetValue(p,kCFNumberIntType,&product);
   if(product==0x5027 || product==0x5a27) { count++; chosen=d; pid=product; }
  }
  free(items);
 }
 int result=0;
 if(count!=1) { snprintf(errorText,sizeof(errorText),"Found %d OMNIKEY 5027 interfaces. Connect exactly one 5027 and try again.",count); result=-1; }
 else if((enable && pid==0x5027)||(!enable && pid==0x5a27)) {
  IOReturn rc=IOHIDDeviceOpen(chosen,kIOHIDOptionsTypeNone);
  if(rc!=kIOReturnSuccess) result=fail("Cannot open the 5027 USB interface",rc);
  else {
   uint8_t report[2]={enable?0xa5:0x5a,enable?0x5a:0xa5};
   rc=IOHIDDeviceSetReport(chosen,kIOHIDReportTypeFeature,0,report,2);
   IOHIDDeviceClose(chosen,kIOHIDOptionsTypeNone);
   if(rc!=kIOReturnSuccess) result=fail("Could not switch the 5027 configuration interface",rc);
  }
 }
 if(devices) CFRelease(devices); CFRelease(manager); return result;
}
void reader_close(void) {
 if(card) { SCardDisconnect(card,SCARD_LEAVE_CARD); card=0; }
 if(context) { SCardReleaseContext(context); context=0; }
 // Switching back does not save staged settings. Unplug/replug also restores keyboard mode.
 switchMode(0);
}
int reader_open(void) {
 errorText[0]=0;
 if(switchMode(1)<0) return -1;
 int32_t rc=SCardEstablishContext(SCARD_SCOPE_SYSTEM,NULL,NULL,&context);
 if(rc!=SCARD_S_SUCCESS) return fail("Cannot start macOS smart-card service",rc);
 for(int attempt=0;attempt<40;attempt++) {
  char names[8192]={0}; uint32_t size=sizeof(names);
  rc=SCardListReaders(context,NULL,names,&size);
  char *selected=NULL; int matches=0;
  if(rc==SCARD_S_SUCCESS) for(char *p=names;*p;p+=strlen(p)+1) {
   if(strstr(p,"5027") && (strstr(p,"OMNIKEY")||strstr(p,"Omnikey"))) {selected=p;matches++;}
  }
  if(matches>1) { snprintf(errorText,sizeof(errorText),"Multiple 5027 smart-card interfaces found. Connect just one reader."); return -1; }
  if(matches==1) {
   directMode=0;
   rc=SCardConnect(context,selected,SCARD_SHARE_SHARED,SCARD_PROTOCOL_T0|SCARD_PROTOCOL_T1,&card,&protocol);
   // macOS PCSC rejects a zero preferred-protocol mask, even for DIRECT.
   if(rc!=SCARD_S_SUCCESS) { directMode=1; rc=SCardConnect(context,selected,SCARD_SHARE_DIRECT,SCARD_PROTOCOL_RAW,&card,&protocol); }
   if(rc!=SCARD_S_SUCCESS) return fail("Cannot connect to the 5027 configuration slot",rc);
   escapeCode=0x42000000U+3500U;
   if(directMode) {
    // PC/SC Part 10: obtain FEATURE_CCID_ESC_COMMAND (0x13).
    // Drivers need not use the legacy pcsc-lite escape control code.
    uint8_t features[256]; uint32_t received=0;
    int32_t featureResult=SCardControl(card,0x42000000U+3400U,NULL,0,features,sizeof(features),&received);
    if(featureResult==SCARD_S_SUCCESS) {
     uint32_t discovered=0;
     if(!parse_escape_feature(features,received,&discovered)) {
      snprintf(errorText,sizeof(errorText),"The driver returned malformed PC/SC feature data. No reader settings were changed.");return -1;
     }
     if(discovered) escapeCode=discovered;
    }
   }
   return 0;
  }
  usleep(250000);
 }
 snprintf(errorText,sizeof(errorText),"macOS did not expose the 5027 configuration slot. Reconnect the reader and try again. This macOS/reader combination may need a compatible CCID driver."); return -1;
}
int reader_exchange(const uint8_t *input,int length,uint8_t *output,int capacity) {
 if(!card) return fail("Reader is not connected",0);
 uint32_t size=(uint32_t)capacity; int32_t rc;
 if(directMode) rc=SCardControl(card,escapeCode,input,(uint32_t)length,output,size,&size);
 else { SCARD_IO_REQUEST pci={protocol,sizeof(SCARD_IO_REQUEST)}; rc=SCardTransmit(card,&pci,input,(uint32_t)length,NULL,output,&size); }
 if(rc!=SCARD_S_SUCCESS) {
  char operation[128];
  if(directMode) snprintf(operation,sizeof(operation),"Configuration exchange failed via SCardControl 0x%08x",escapeCode);
  else snprintf(operation,sizeof(operation),"Configuration exchange failed via SCardTransmit (protocol %u)",protocol);
  return fail(operation,rc);
 }
 return (int)size;
}
