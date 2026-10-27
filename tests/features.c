#include "../Features.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 uint32_t code;
 uint8_t features[]={0x06,4,0x42,0x33,0,6,0x13,4,0x42,0x33,0,0x13};
 assert(parse_escape_feature(features,sizeof(features),&code)&&code==0x42330013);
 assert(parse_escape_feature(features,6,&code)&&code==0);
 assert(parse_escape_feature(NULL,0,&code)&&code==0);
 for(size_t n=7;n<12;n++)assert(!parse_escape_feature(features,n,&code));
 uint8_t bad[]={0x13,3,1,2,3};assert(!parse_escape_feature(bad,sizeof(bad),&code));
 uint8_t duplicate[]={0x13,4,1,2,3,4,0x13,4,1,2,3,4};assert(!parse_escape_feature(duplicate,sizeof(duplicate),&code));
 puts("PASS: feature discovery, byte order, absent escape feature, truncated and malformed records");
}
