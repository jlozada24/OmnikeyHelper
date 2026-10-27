#ifndef OMNIKEY_FEATURES_H
#define OMNIKEY_FEATURES_H
#include <stdint.h>
#include <stddef.h>
// Feature records are tag, length, and a four-byte network-order control code.
static int parse_escape_feature(const uint8_t *data,size_t length,uint32_t *code) {
 *code=0;
 for(size_t offset=0;offset<length;) {
  if(length-offset<2) return 0;
  uint8_t tag=data[offset],size=data[offset+1];offset+=2;
  if(size!=4 || length-offset<size) return 0;
  if(tag==0x13) {
   if(*code) return 0;
   *code=((uint32_t)data[offset]<<24)|((uint32_t)data[offset+1]<<16)|((uint32_t)data[offset+2]<<8)|data[offset+3];
   if(!*code) return 0;
  }
  offset+=size;
 }
 return 1;
}
#endif
