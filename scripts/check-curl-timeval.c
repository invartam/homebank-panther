/* Legacy BSD headers require sys/types.h before socket/time declarations. */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>

int main(void)
{
    struct timeval value;
    value.tv_sec = 0;
    value.tv_usec = 0;
    return (int)(value.tv_sec + value.tv_usec);
}
