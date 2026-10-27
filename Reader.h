#include <stdint.h>
int reader_open(void);
int reader_exchange(const uint8_t *input, int length, uint8_t *output, int capacity);
void reader_close(void);
const char *reader_error(void);
