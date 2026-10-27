#include <stdint.h>
int usb_open(void);
int usb_exchange(const uint8_t*,int,uint8_t*,int);
void usb_close(void);
const char *usb_error(void);
int usb_capture(void);
void usb_release(void);
