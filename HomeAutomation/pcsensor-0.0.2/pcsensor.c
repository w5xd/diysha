/*
 * pcsensor.c by Juan Carlos Perez (c) 2011 (cray@isp-sl.com)
 * based on Temper.c by Robert Kavaler (c) 2009 (relavak.com)
 * All rights reserved.
 *
 * Temper driver for linux. This program can be compiled either as a library
 * or as a standalone program (-DUNIT_TEST). The driver will work with some
 * TEMPer usb devices from RDing (www.PCsensor.com).
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 * 
 * THIS SOFTWARE IS PROVIDED BY Juan Carlos Perez ''AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL Robert kavaler BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * Wayne Wright, modified June 23, 2012.
 * write all error messages to stderr (instead of some to stdout)
 * print two temperatures for the 2-sensor device
 * format output using tabs (for easy spreadsheet import)
 *
 * Wayne Wright, August 5, 2012
 * Port to libusb-win32
 * http://sourceforge.net/apps/trac/libusb-win32/wiki
 * pcsensor.exe is the only thing "we" build. The
 * other stuff needed on the end-user machine is from libusb-win32.
 * That package has inf-wizard.exe. Run that program twice, once
 * for Interface 0 on the TEMPer2, and again for Interface 1.
 * It creates some files that look like they might be installable
 * separately. My experience is no--they are just temporary files
 * that can be deleted after the install.
 *
 * WIN32 and LINUX32 are not really the same.
 * This was written by cutting and trying until it worked on WIN32
 * while preserving the LINUX32 behavior.
 */

/* On Linux
** Requires both libusb and libusb-compat
** libusb.org
** Builds with libusb-1.0.9
**             libusb-compat-0.1.4
*/

#include <stdio.h>
#include <time.h>
#include <string.h>
#include <errno.h>

#if defined(LINUX32)
#include <usb.h>
#include <signal.h> 
#elif defined (WIN32)
#include <lusb0_usb.h>
#endif
 
#if defined (WIN32)
static void bzero(void *v, size_t s){memset(v, 0, s);}
static void sleep(int seconds){::Sleep(seconds*1000);}
#endif
 
#define VERSION "0.0.2"
 
#define VENDOR_ID  0x0c45
#define PRODUCT_ID 0x7401
 
#define INTERFACE1 0x00
#define INTERFACE2 0x01
 
const static int reqIntLen=8;
const static int reqBulkLen=8;
const static int endpoint_Int_in=0x82; /* endpoint 0x81 address for IN */
const static int endpoint_Int_out=0x00; /* endpoint 1 address for OUT */
const static int endpoint_Bulk_in=0x82; /* endpoint 0x81 address for IN */
const static int endpoint_Bulk_out=0x00; /* endpoint 1 address for OUT */
const static int timeout=5000; /* timeout in ms */
 
const static char uTemperatura[] = { 0x01, 0x80, 0x33, 0x01, 0x00, 0x00, 0x00, 0x00 };
const static char uIni1[] = { 0x01, 0x82, 0x77, 0x01, 0x00, 0x00, 0x00, 0x00 };
const static char uIni2[] = { 0x01, 0x86, 0xff, 0x01, 0x00, 0x00, 0x00, 0x00 };

static int bsalir=1;
static int debug=0;
static int seconds=5;
static int formato=0;
static int mrtg=0;

void bad(const char *why) {
        fprintf(stderr,"Fatal error> %s\n",why);
        exit(17);
}
  
usb_dev_handle *find_lvr_winusb(int w);

void usb_detach(usb_dev_handle *lvr_winusb, int iInterface) {
#if defined (LIBUSB_HAS_DETACH_KERNEL_DRIVER_NP)
    int ret;
    ret = usb_detach_kernel_driver_np(lvr_winusb, iInterface);
    if(ret) {
        if(errno == ENODATA) {
            if(debug) {
                printf("Device already detached\n");
            }
        } else {
            if(debug) {
                printf("Detach failed: %s[%d]\n",
                    strerror(errno), errno);
                printf("Continuing anyway\n");
            }
        }
    } else {
        if(debug) {
            printf("detach successful\n");
        }
    }
#endif
} 

usb_dev_handle* setup_libusb_access(int w, int w2) {
    usb_dev_handle *lvr_winusb;

    if(debug) {
        usb_set_debug(255);
    } else {
        usb_set_debug(0);
    }

    usb_init();
    usb_find_busses();
    usb_find_devices();

    if(!(lvr_winusb = find_lvr_winusb(w))) {
        fprintf(stderr,"Couldn't find the USB device\n");
        return NULL;
    }

#if defined (LINUX32)
    usb_detach(lvr_winusb, w2);
#endif
    usb_detach(lvr_winusb, w);

    if (usb_set_configuration(lvr_winusb, 0x01) < 0) {
        fprintf(stderr, "Could not set configuration 1\n");
        return NULL;
    }

    // Microdia tiene 2 interfaces
#if defined (LINUX32)
    if (usb_claim_interface(lvr_winusb, w2) < 0)
    {
        fprintf(stderr, "Could not claim interface\n");
        return NULL;
    }
#endif
    if (usb_claim_interface(lvr_winusb, w) < 0)
    {
        fprintf(stderr, "Could not claim interface\n");
        return NULL;
    }

    return lvr_winusb;
}

usb_dev_handle *find_lvr_winusb(int w) {

    struct usb_bus *bus;
    struct usb_device *dev;
    usb_dev_handle *handle=NULL;
    int ii;
    for (bus = usb_busses; bus; bus = bus->next) {
        for (dev = bus->devices; dev; dev = dev->next) {
            if (dev->descriptor.idVendor == VENDOR_ID && 
                dev->descriptor.idProduct == PRODUCT_ID ) {
                    if(debug) {
                        printf("lvr_winusb with Vendor Id: %x and Product Id: %x found. alts:%d.\n", 
                            VENDOR_ID, PRODUCT_ID,
                            dev->config->interface->num_altsetting);
                    }
                    for (ii =0; ii < dev->config->interface->num_altsetting; ii++)
                    {
#if defined(WIN32)  
                        // WIN32 is different--the bInterface number must match up to claimInterface
                        if (dev->config->interface->altsetting[ii].bInterfaceNumber == w)
#endif
                        {
                            if (!(handle = usb_open(dev))) 
                            {
                                fprintf(stderr,"Could not open USB device\n");
                                return NULL;
                            }
                            break;
                        }
                    }
            }
        }
    }
    return handle;
}

void ini_control_transfer(usb_dev_handle *dev) {
    int r,i;

    char question[] = { 0x01,0x01 };

    r = usb_control_msg(dev, 0x21, 0x09, 0x0201, 0x00, (char *) question, 2, timeout);
    if( r < 0 )
    {
        perror("USB control write"); bad("USB write failed"); 
    }

    if(debug) {
        for (i=0;i<reqIntLen; i++) printf("%02x ",question[i] & 0xFF);
        printf("\n");
    }
}

void control_transfer(usb_dev_handle *dev, const char *pquestion) {
    int r,i;

    char question[reqIntLen];

    memcpy(question, pquestion, sizeof question);

    r = usb_control_msg(dev, 0x21, 0x09, 0x0200, 0x01, (char *) question, reqIntLen, timeout);
    if( r < 0 )
    {
        perror("USB control write"); bad("USB write failed"); 
    }

    if(debug) {
        for (i=0;i<reqIntLen; i++) printf("%02x ",question[i]  & 0xFF);
        printf("\n");
    }
}

void interrupt_transfer(usb_dev_handle *dev) {

    int r,i;
    char answer[reqIntLen];
    char question[reqIntLen];
    for (i=0;i<reqIntLen; i++) question[i]=i;
    r = usb_interrupt_write(dev, endpoint_Int_out, question, reqIntLen, timeout);
    if( r < 0 )
    {
        perror("1 USB interrupt write"); bad("USB write failed"); 
    }
    r = usb_interrupt_read(dev, endpoint_Int_in, answer, reqIntLen, timeout);
    if( r != reqIntLen )
    {
        perror("1 USB interrupt read"); bad("USB read failed"); 
    }

    if(debug) {
        for (i=0;i<reqIntLen; i++) printf("%i, %i, \n",question[i],answer[i]);
    }

    usb_release_interface(dev, 0);
}

void interrupt_read(usb_dev_handle *dev) {

    int r,i;
    unsigned char answer[reqIntLen];
    bzero(answer, reqIntLen);

    r = usb_interrupt_read(dev, 0x82, (char*)(answer), reqIntLen, timeout);
    if( r != reqIntLen )
    {
        perror("2 USB interrupt read"); bad("USB read failed"); 
    }

    if(debug) {
        for (i=0;i<reqIntLen; i++) printf("%02x ",answer[i]  & 0xFF);

        printf("\n");
    }
}

static int to16Bits(int t)
{
    // assumes sizeof(int) is any size of 16 bit or wider
    if (t & 0x8000) // should have been negative
    {
        int mask = -1;
        mask ^= 0xFFFF; // remove the data bits from the sign extend mask
        t |= mask;  // extend the sign bits to the top of the int
    }
    return t;
}

void interrupt_read_temperatura(usb_dev_handle *dev, float *tempC, float *tempC2) {

    int r,i, temperature;
    unsigned char answer[reqIntLen];
    bzero(answer, reqIntLen);

    r = usb_interrupt_read(dev, 0x82, (char*)(answer), reqIntLen, timeout);
    if( r != reqIntLen )
    {
        perror("3 USB interrupt read"); bad("USB read failed"); 
    }

    if(debug) {
        for (i=0;i<reqIntLen; i++) printf("%02x ",answer[i]  & 0xFF);

        printf("\n");
    }

    temperature = to16Bits((answer[3] & 0xFF) + (answer[2] << 8));
    *tempC = temperature * (125.0 / 32000.0);
    temperature = to16Bits((answer[5] & 0xFF) + (answer[4] << 8));
    *tempC2 = temperature * (125.0 / 32000.0);
}

#if 0   // this code is not used anywhere
void bulk_transfer(usb_dev_handle *dev) {

    int r,i;
    char answer[reqBulkLen];

    r = usb_bulk_write(dev, endpoint_Bulk_out, NULL, 0, timeout);
    if( r < 0 )
    {
        perror("USB bulk write"); bad("USB write failed"); 
    }
    r = usb_bulk_read(dev, endpoint_Bulk_in, answer, reqBulkLen, timeout);
    if( r != reqBulkLen )
    {
        perror("USB bulk read"); bad("USB read failed"); 
    }

    if(debug) {
        for (i=0;i<reqBulkLen; i++) printf("%02x ",answer[i]  & 0xFF);
    }

    usb_release_interface(dev, 0);
}
#endif

#if defined (LINUX32)
void ex_program(int sig) {
    bsalir=1;

    (void) signal(SIGINT, SIG_DFL);
}
#endif

float cToF(float c){return 32.0 + 9.0 * c / 5.0;}

int main( int argc, char **argv) {
    usb_dev_handle *lvr_winusb = NULL;
    float tempc1, tempc2;
    struct tm *local;
    time_t t;
    int argnum;

    for (argnum = 1; argnum < argc; argnum++ )
    {
        const char *optArg = argv[argnum];
        if ((strlen(optArg) == 2) && (optArg[0] == '-'))
        {
            char optopt = optArg[1];
            switch (optopt)
            {
            case 'v':
                debug = 1;
                break;
            case 'c':
                formato=1; //Celsius
                break;
            case 'f':
                formato=2; //Fahrenheit
                break;
            case 'm':
                mrtg=1;
                break;
            case 'l':
                {
                    const char *optarg = NULL;
                    if ((argnum < argc-1) && (argv[argnum+1][0] != '-'))
                    {
                        argnum += 1;
                        optarg = argv[argnum];
                    }
                    if (optarg!=NULL){
                        if (!sscanf(optarg,"%i",&seconds)==1) {
                            fprintf (stderr, "Error: '%s' is not numeric.\n", optarg);
                            exit(EXIT_FAILURE);
                        } else {           
                            bsalir = 0;
                            break;
                        }
                    } else {
                        bsalir = 0;
                        seconds = 5;
                        break;
                    }
                }
            case '?':
            case 'h':
                printf("pcsensor version %s\n",VERSION);
                printf("      Aviable options:\n");
                printf("          -h help\n");
                printf("          -v verbose\n");
                printf("          -l [n] loop every 'n' seconds, default value is 5s\n");
                printf("          -c output only in Celsius\n");
                printf("          -f output only in Fahrenheit\n");
                printf("          -m output for mrtg integration\n");

                exit(EXIT_FAILURE);
            default:
                if (isprint (optopt))
                    fprintf (stderr, "Unknown option `-%c'.\n", optopt);
                else
                    fprintf (stderr,
                    "Unknown option character `\\x%x'.\n",
                    optopt);
                exit(EXIT_FAILURE);
            }
        }
        else {
            fprintf(stderr, "Non-option ARGV-elements, try -h for help.\n");
            exit(EXIT_FAILURE);
        }
    }


    if ((lvr_winusb = setup_libusb_access(INTERFACE2, INTERFACE1)) == NULL) {
        exit(EXIT_FAILURE);
    } 

#if defined (LINUX32)
    (void) signal(SIGINT, ex_program);
#endif

    ini_control_transfer(lvr_winusb);

    control_transfer(lvr_winusb, uTemperatura );
    interrupt_read(lvr_winusb);

    control_transfer(lvr_winusb, uIni1 );
    interrupt_read(lvr_winusb);

    control_transfer(lvr_winusb, uIni2 );
    interrupt_read(lvr_winusb);
    interrupt_read(lvr_winusb);

    do {
        control_transfer(lvr_winusb, uTemperatura );
        interrupt_read_temperatura(lvr_winusb, &tempc1, &tempc2);

        t = time(NULL);
        local = localtime(&t);

        if (mrtg) {
            if (formato==2) {
                printf("%.2f\n", cToF(tempc1));
                printf("%.2f\n", cToF(tempc1));
            } else {
                printf("%.2f\n", tempc1);
                printf("%.2f\n", tempc1);
            }

            printf("%02d:%02d\n", 
                local->tm_hour,
                local->tm_min);

            printf("pcsensor\n");
        } else {
            printf("%04d/%02d/%02d\t%02d:%02d:%02d\t", 
                local->tm_year +1900, 
                local->tm_mon + 1, 
                local->tm_mday,
                local->tm_hour,
                local->tm_min,
                local->tm_sec);

            if (formato==2) {
                printf("Temperature(F)\t%.2f\t%.2f\n", cToF(tempc1), cToF(tempc2));
            } else if (formato==1) {
                printf("Temperature(C)\t%.2f\t%.2f\n", tempc1, tempc2);
            } else {
                printf("Temperature %.2fF %.2fF, %.2fC %.2fC\n", cToF(tempc1), cToF(tempc2), tempc2, tempc1);
            }
        }

        if (!bsalir)
            sleep(seconds);
    } while (!bsalir);

#if defined (LINUX32)
    usb_release_interface(lvr_winusb, INTERFACE1);
#endif
    usb_release_interface(lvr_winusb, INTERFACE2);
    usb_close(lvr_winusb); 

    return 0; 
}
