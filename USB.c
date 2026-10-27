#include "USB.h"
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static IOUSBInterfaceInterface300 **iface;
static UInt8 inPipe,outPipe,sequence;
static char error[256];
const char *usb_error(void){return error;}
static int fail(const char *s,IOReturn r){snprintf(error,sizeof(error),"%s: 0x%08x",s,r);return -1;}
static int property(io_service_t s,CFStringRef key){int x=-1;CFTypeRef v=IORegistryEntrySearchCFProperty(s,kIOServicePlane,key,NULL,kIORegistryIterateRecursively|kIORegistryIterateParents);if(v){if(CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue(v,kCFNumberIntType,&x);CFRelease(v);}return x;}
void usb_close(void){if(iface){(*iface)->USBInterfaceClose(iface);(*iface)->Release(iface);iface=NULL;}}
int usb_open(void){
 io_iterator_t it=0;IOReturn r=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostInterface"),&it);if(r)return fail("Enumerating USB interfaces",r);
 io_service_t s,selected=0;int matches=0;
 while((s=IOIteratorNext(it))){
  if(property(s,CFSTR("idVendor"))==0x076b && property(s,CFSTR("idProduct"))==0x5a27 && property(s,CFSTR("bInterfaceClass"))==11){matches++;if(selected)IOObjectRelease(selected);selected=s;}else IOObjectRelease(s);
 }
 IOObjectRelease(it);
 if(matches!=1){if(selected)IOObjectRelease(selected);snprintf(error,sizeof(error),"Found %d matching USB CCID interfaces",matches);return -1;}
 IOCFPlugInInterface **plugin=NULL;SInt32 score=0;
 r=IOCreatePlugInInterfaceForService(selected,kIOUSBInterfaceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);IOObjectRelease(selected);if(r)return fail("Creating USB interface client",r);
 HRESULT h=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),(void**)&iface);IODestroyPlugInInterface(plugin);if(h||!iface)return fail("Querying USB interface",h);
 r=(*iface)->USBInterfaceOpen(iface);if(r==kIOReturnExclusiveAccess)r=(*iface)->USBInterfaceOpenSeize(iface);if(r){(*iface)->Release(iface);iface=NULL;return fail("Opening USB CCID interface",r);}
 UInt8 n=0;(*iface)->GetNumEndpoints(iface,&n);inPipe=outPipe=0;
 for(UInt8 p=1;p<=n;p++){UInt8 direction,number,type,interval;UInt16 packet;r=(*iface)->GetPipeProperties(iface,p,&direction,&number,&type,&packet,&interval);if(!r && type==kUSBBulk){if(direction==kUSBIn)inPipe=p;else if(direction==kUSBOut)outPipe=p;}}
 if(!inPipe||!outPipe){usb_close();return fail("Missing CCID bulk endpoints",0);}
 return 0;
}
int usb_exchange(const uint8_t *input,int length,uint8_t *output,int capacity){
 if(!iface||length<0||length>255)return fail("Invalid USB exchange",0);
 uint8_t request[265]={0x6b}; // PC_to_RDR_Escape, slot zero
 request[1]=length;request[6]=++sequence;memcpy(request+10,input,length);
 IOReturn r=(*iface)->WritePipeTO(iface,outPipe,request,length+10,2000,4000);if(r)return fail("Writing CCID Escape",r);
 for(int attempts=0;attempts<16;attempts++){
  uint8_t response[1024];UInt32 size=sizeof(response);r=(*iface)->ReadPipeTO(iface,inPipe,response,&size,2000,4000);if(r)return fail("Reading CCID Escape",r);
  if(size<10){snprintf(error,sizeof(error),"Truncated CCID header: %u bytes",size);return -1;}
  if(response[0]!=0x83||response[5]!=0||response[6]!=sequence){
   if(getenv("OMNIKEY_DIAGNOSTICS"))fprintf(stderr,"Skipping previous USB reply: type=%02x slot=%02x seq=%02x (expected %02x), bytes=%u\n",response[0],response[5],response[6],sequence,size);
   continue;
  }
  unsigned count=response[1]|((unsigned)response[2]<<8)|((unsigned)response[3]<<16)|((unsigned)response[4]<<24);
  if((response[7]&0xc0)==0x80)continue;
  if((response[7]&0xc0)!=0){snprintf(error,sizeof(error),"CCID status %02x error %02x",response[7],response[8]);return -1;}
  if(count!=size-10||count>(unsigned)capacity)return fail("Invalid CCID payload length",0);
  memcpy(output,response+10,count);return count;
 }
 return fail("CCID time extension limit",0);
}

// One-device capture test. Root authorization is required by macOS.
#include <unistd.h>
static IOUSBDeviceInterface500 **device;
static int devicePID;
static void releaseHandle(void){if(device){(*device)->USBDeviceClose(device);(*device)->Release(device);device=NULL;}}
static int findDevice(void){
 io_iterator_t it=0;IOReturn r=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostDevice"),&it);if(r)return fail("Enumerating reader device",r);
 io_service_t s,chosen=0;int n=0,total=0;
 while((s=IOIteratorNext(it))){total++;int pid=property(s,CFSTR("idProduct"));if(property(s,CFSTR("idVendor"))==0x076b&&(pid==0x5027||pid==0x5a27)){n++;if(chosen)IOObjectRelease(chosen);chosen=s;devicePID=pid;}else IOObjectRelease(s);}
 IOObjectRelease(it);if(n!=1){if(chosen)IOObjectRelease(chosen);snprintf(error,sizeof(error),"Connect exactly one 5027 (found %d among %d USB devices, uid=%u euid=%u)",n,total,getuid(),geteuid());return -1;}
 IOCFPlugInInterface **plugin=NULL;SInt32 score;
 r=IOCreatePlugInInterfaceForService(chosen,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);IOObjectRelease(chosen);if(r)return fail("Creating device client",r);
 HRESULT h=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID500),(void**)&device);IODestroyPlugInInterface(plugin);if(h||!device)return fail("Querying device client",h);return 0;
}
static IOReturn switchUSB(int enable){uint8_t report[2]={enable?0xa5:0x5a,enable?0x5a:0xa5};IOUSBDevRequest req={.bmRequestType=0x21,.bRequest=9,.wValue=0x0300,.wIndex=0,.wLength=2,.pData=report};return (*device)->DeviceRequest(device,&req);}
void usb_release(void){usb_close();if(device){switchUSB(0);(*device)->USBDeviceReEnumerate(device,kUSBReEnumerateReleaseDeviceMask);releaseHandle();}}
static int captureOnce(void){
 if(geteuid()!=0)return fail("Administrator authorization required for temporary reader capture",kIOReturnNotPrivileged);
 for(int pass=0;pass<2;pass++){
  int found=-1;for(int retry=0;retry<40;retry++){found=findDevice();if(found==0)break;usleep(250000);}if(found<0)return -1;
  if(getenv("OMNIKEY_DIAGNOSTICS"))fprintf(stderr,"Found 5027 USB mode %04x (pass %d)\n",devicePID,pass+1);
  IOReturn r=(*device)->USBDeviceReEnumerate(device,kUSBReEnumerateCaptureDeviceMask);if(r){releaseHandle();return fail("Capturing only the 5027",r);}
  if(getenv("OMNIKEY_DIAGNOSTICS"))fprintf(stderr,"Captured the 5027\n");
  usleep(300000);
  r=(*device)->USBDeviceOpenSeize(device);if(r){usb_release();return fail("Opening captured reader",r);}
  if(devicePID==0x5027){r=switchUSB(1);if(getenv("OMNIKEY_DIAGNOSTICS"))fprintf(stderr,"Requested configuration mode: %08x\n",r);releaseHandle();usleep(1000000);continue;}
  for(int n=0;n<20;n++){if(usb_open()==0)return 0;usleep(100000);}
  char saved[256];strlcpy(saved,error,sizeof(saved));usb_release();strlcpy(error,saved,sizeof(error));return -1;
 }
 return fail("Configuration interface did not appear",0);
}
int usb_discover(void){int r=findDevice();if(r==0){fprintf(stderr,"Discovered product %04x\n",devicePID);releaseHandle();}return r;}

int usb_capture(void){
 for(int attempt=0;attempt<3;attempt++) {
  int r=captureOnce();if(r==0)return 0;
  char saved[256];strlcpy(saved,error,sizeof(saved));usb_release();strlcpy(error,saved,sizeof(error));
  if(geteuid()!=0)return -1;
  if(attempt<2){fprintf(stderr,"Waiting for the reader to reconnect...\n");usleep(1500000);}
 }
 return -1;
}
