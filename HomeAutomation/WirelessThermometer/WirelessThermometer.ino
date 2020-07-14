#include <RadioConfiguration.h>
#include <SPI.h>
#include <EEPROM.h>
#include <avr/sleep.h>
#include <avr/interrupt.h>
#include <avr/power.h>

// SparkFun's part numbers are:
// 915MHz: https://www.sparkfun.com/products/12775
// 434MHz: https://www.sparkfun.com/products/12823

// Parts of the code in this sketch are taken from these sparkfun pages,
// as are all the wiring instructions:
// https://learn.sparkfun.com/tutorials/rfm69hcw-hookup-guide
// https://learn.sparkfun.com/tutorials/tmp102-digital-temperature-sensor-hookup-guide

// Uses the RFM69 library by Felix Rusu, LowPowerLab.com
// Original library: https://www.github.com/lowpowerlab/rfm69

// code only supports a TMP102 sensor or HIH6130 but not both
#define USE_TMP102
// The TMP102 has temperature only, -40C to 100C
//#define USE_HIH6130
// The HIH6130 has temperature and relative humidity, -20C to 85C

//#define SLEEP_TMP102_ONLY /* for testing only*/

// Include the RFM69 and SPI libraries:
#define USE_RFM69
//#define SLEEP_RFM69_ONLY /* for testing only */
#define USE_SERIAL
#define TELEMETER_BATTERY_V

// Using TIMER2 to sleep costs about 200uA of sleep-time current, but saves the 1uF/10Mohm external parts
//#define SLEEP_WITH_TIMER2

#if defined(USE_RFM69)
#include <RFM69.h>
#include <RFM69registers.h>
#endif

#if defined(USE_TMP102)
#include <Wire.h>
#include "TMP102Helper.h" // Used to send and receive specific information from our sensor
#elif defined(USE_HIH6130)
#include "HIH6130Helper.h"
#endif

namespace {
const int BATTERY_PIN = A0; // digitize (fraction of) battery voltage
const int TIMER_RC_GROUND_PIN = 4;
const int TIMER_RC_PIN = 3; // sleep uProc using RC circuit on this pin

const uint32_t FirstListenAfterTransmitMsec = 20000;// at system reset, listen Serial/RF for this long
uint32_t NormalListenAfterTransmit = 300;// after TX, go to RX for this long

#if defined(USE_TMP102)
// Connections to TMP102
// VCC = 3.3V
// GND = GND
// SDA = A4
// SCL = A5
const int ALERT_PIN = A3;

HomeAutomationTools::TMP102 sensor0(0x48); // Initialize sensor at I2C address 0x48
// Sensor address can be changed with an external jumper to:
// ADD0 - Address
//  VCC - 0x49
//  SDA - 0x4A
//  SCL - 0x4B
#elif defined(USE_HIH6130)
HomeAutomationTools::HIH6130 sensor0;
/* The connection is SDA(A4), SCL(A5), VDD and GND to the HIH6130 */
#endif

#if defined(USE_RFM69)
// RFM69 frequency, uncomment the frequency of your module:

//#define FREQUENCY   RF69_433MHZ
#define FREQUENCY     RF69_915MHZ

// AES encryption (or not):
const bool ENCRYPT = true; // Set to "true" to use encryption
// Use ACKnowledge when sending messages (or not):
const bool USEACK = true; // Request ACKs or not
const int RFM69_RESET_PIN = A1;
const uint8_t GATEWAY_NODEID = 1;

class SleepRFM69 : public RFM69
{
public:
    void startAsleep()
    {
      digitalWrite(_slaveSelectPin, HIGH);
      pinMode(_slaveSelectPin, OUTPUT);
      SPI.begin();
      SPIoff();
    }

    void SPIoff()
    {
        // this command drops the idle current by about 100 uA...maybe
        // I could not get consistent results. so I left it in
        writeReg(REG_OPMODE, (readReg(REG_OPMODE) & 0xE3) | RF_OPMODE_SLEEP | RF_OPMODE_LISTENABORT);
         _mode = RF69_MODE_STANDBY; // force base class do the write
        sleep();
        SPI.end();

        // set high impedance for all pins connected to RFM69
        // ...except VDD, of course
        pinMode(PIN_SPI_MISO, INPUT);
        pinMode(PIN_SPI_MOSI, INPUT);
        pinMode(PIN_SPI_SCK, INPUT);
        pinMode(PIN_SPI_SS, INPUT);
        pinMode(_slaveSelectPin, INPUT);
    }
    void SPIon()
    {
      digitalWrite(_slaveSelectPin, HIGH);
      pinMode(_slaveSelectPin, OUTPUT);
      SPI.begin();
    }
};
// Create a library object for our RFM69HCW module:
SleepRFM69 radio;
#endif

#if defined(TELEMETER_BATTERY_V)
void ResetAnalogReference();
#endif

RadioConfiguration radioConfiguration;
unsigned long TimeOfWakeup;
const unsigned MAX_SLEEP_LOOP_COUNT = 5000; // a couple times per day is minimum check-in interval
unsigned SleepLoopTimerCount = 30; // approx 10 seconds per Count

int SleepCountPos() { return RadioConfiguration::TotalEpromUsed();}
int ListenAfterTransmitPos() { return SleepCountPos() + sizeof(unsigned); }
}

void setup()
{
    const char * const key = radioConfiguration.EncryptionKey();
#if defined(USE_SERIAL)
    // Open a serial port so we can send keystrokes to the module:

    Serial.begin(9600);
    Serial.print("Node ");
    Serial.print(radioConfiguration.NodeId(), DEC);
    Serial.print(" on network ");
    Serial.print(radioConfiguration.NetworkId(), DEC);
    Serial.print(" band ");
    Serial.print(radioConfiguration.FrequencyBandId(), DEC);
    if (ENCRYPT) {
        if (radioConfiguration.encrypted()) {
            Serial.print(" key "); 
            for (int i = 0; i < RadioConfiguration::ENCRYPT_KEY_LENGTH; i++)
            {
            char c = key[i];
            if (isprint(c)) Serial.print(c);
            else
            {
               Serial.print(" 0x"); Serial.print((int)(unsigned char)c, HEX); Serial.print(" ");
            }
            }
        }
    }
    Serial.println(" ready");
#endif

#if defined(USE_TMP102)
    pinMode(ALERT_PIN, INPUT);  // Declare alertPin as an input
    sensor0.begin();  // Join I2C bus
    // Initialize sensor0 settings
    sensor0.setOneShotMode(); // set low power mode

    // These settings are saved in the sensor, even if it loses power

    // set the number of consecutive faults before triggering alarm.
    // 0-3: 0:1 fault, 1:2 faults, 2:4 faults, 3:6 faults.
    sensor0.setFault(0);  // Trigger alarm immediately

    // set the polarity of the Alarm. (0:Active LOW, 1:Active HIGH).
    sensor0.setAlertPolarity(0); // Active LOW

    // set the sensor in Comparator Mode (0) or Interrupt Mode (1).
    sensor0.setAlertMode(0); // Comparator Mode.

    // set the Conversion Rate (how quickly the sensor gets a new reading)
    //0-3: 0:0.25Hz, 1:1Hz, 2:4Hz, 3:8Hz
    sensor0.setConversionRate(2);

    //set Extended Mode.
    //0:12-bit Temperature(-55C to +128C) 1:13-bit Temperature(-55C to +150C)
    sensor0.setExtendedMode(0);

    //set T_HIGH, the upper limit to trigger the alert on
    sensor0.setHighTempC(127); // set T_HIGH in C

    //set T_LOW, the lower limit to shut turn off the alert
    sensor0.setLowTempC(127); // set T_LOW in C

    sensor0.end();
#endif

#if defined(USE_RFM69)
    //digitalWrite(RFM69_RESET_PIN, LOW);
    //pinMode(RFM69_RESET_PIN, OUTPUT);

#if !defined(SLEEP_RFM69_ONLY)
    // Initialize the RFM69HCW:
    auto ok = radio.initialize(radioConfiguration.FrequencyBandId(),
        radioConfiguration.NodeId(), radioConfiguration.NetworkId());
#if defined(USE_SERIAL)
    Serial.println(ok ? "Radio init OK" : "Radio init failed");
    if (ok)
    {
        uint32_t freq;
        if (radioConfiguration.FrequencyKHz(freq))
            radio.setFrequency(1000*freq);
        Serial.print("Freq= "); Serial.print(radio.getFrequency()/1000); Serial.println(" KHz");
    }
#endif   

    radio.setHighPower(); // Always use this for RFM69HCW
    // Turn on encryption if desired:

    if (ENCRYPT && radioConfiguration.encrypted())
        radio.encrypt(key);
#else
    radio.startAsleep();
#endif

#endif

#if defined(TELEMETER_BATTERY_V)
    ResetAnalogReference();
#endif

    digitalWrite(TIMER_RC_GROUND_PIN, LOW);
    pinMode(TIMER_RC_GROUND_PIN, OUTPUT);

    TimeOfWakeup = millis(); // start loop timer now

    unsigned eepromLoopCount(0);
    EEPROM.get(SleepCountPos(), eepromLoopCount);
    if (eepromLoopCount && eepromLoopCount <= MAX_SLEEP_LOOP_COUNT)
        SleepLoopTimerCount = eepromLoopCount;
#if defined(USE_SERIAL)
    Serial.print("SleepLoopTimerCount = "); Serial.println(SleepLoopTimerCount, DEC);
#endif

    uint32_t law;
    EEPROM.get(ListenAfterTransmitPos(), law);
    if (law != 0xffffffffl)
        NormalListenAfterTransmit = law;
#if defined(USE_SERIAL)
    Serial.print("ListenAfterTransmitMsec = "); Serial.println(NormalListenAfterTransmit, DEC);
#endif
}

/* Power management:
 * For ListenAfterTransmitMsec we stay awake and listen on the radio and Serial.
 * Then we power down all: temperature sensor, radio and CPU and CPU
 * sleep using SleepTilNextSample.
 */

namespace {
    unsigned SleepTilNextSample();

    uint32_t ListenAfterTransmitMsec = FirstListenAfterTransmitMsec;
    unsigned int sampleCount;

    bool processCommand(const char *pCmd)
    {
        static const char SET_LOOPCOUNT[] = "SetDelayLoopCount";
        static const char SET_LISTENAFTERXMIT[] = "SetListenAfterTransmit";
        if (strncmp(pCmd, SET_LOOPCOUNT, sizeof(SET_LOOPCOUNT) - 1) == 0)
        {
            pCmd = RadioConfiguration::SkipWhiteSpace(
                    pCmd +  sizeof(SET_LOOPCOUNT)-1);
            if (pCmd)
            {
                unsigned v = RadioConfiguration::toDecimalUnsigned(pCmd);
                // don't allow zero, nor more than MAX_SLEEP_LOOP_COUNT
                if (v && v < MAX_SLEEP_LOOP_COUNT)
                {
                    SleepLoopTimerCount = v;
                    EEPROM.put(SleepCountPos(), SleepLoopTimerCount);
                    return true;
                }
            }
        } else if (strncmp(pCmd, SET_LISTENAFTERXMIT, sizeof(SET_LISTENAFTERXMIT)-1) == 0)
        {
            pCmd = RadioConfiguration::SkipWhiteSpace(pCmd + sizeof(SET_LISTENAFTERXMIT)-1);
            if (pCmd)
            {
                uint32_t v = RadioConfiguration::toDecimalUnsigned(pCmd);
                if (v) {
                     NormalListenAfterTransmit = v;
                     EEPROM.put(ListenAfterTransmitPos(), v);
                    return true;
                }
            }
        }
        return false;
    }
}

void loop()
{
    unsigned long now = millis();

#if defined(USE_SERIAL)
    // Set up a "buffer" for characters that we'll send:
    static char sendbuffer[62];
    static int sendlength = 0;
    // In this section, we'll gather serial characters and
    // send them to the other node if we (1) get a carriage return,
    // or (2) the buffer is full (61 characters).

    // If there is any serial input, add it to the buffer:

    if (Serial.available() > 0)
    {
        TimeOfWakeup = now; // extend timer while we hear something
        char input = Serial.read();

        if (input != '\r') // not a carriage return
        {
            sendbuffer[sendlength] = input;
            sendlength++;
        }

        // If the input is a carriage return, or the buffer is full:

        if ((input == '\r') || (sendlength == sizeof(sendbuffer) - 1)) // CR or buffer full
        {
            sendbuffer[sendlength] = 0;
            if (processCommand(sendbuffer))
            {
                Serial.print(sendbuffer);
                Serial.println(" command accepted for thermometer");
            }
            else if (radioConfiguration.ApplyCommand(sendbuffer))
            {
                Serial.print(sendbuffer);
                Serial.println(" command accepted for radio");
            }
            sendlength = 0; // reset the packet
        }
    }
#endif

#if defined(USE_RFM69) && !defined(SLEEP_RFM69_ONLY)
    // RECEIVING
    // In this section, we'll check with the RFM69HCW to see
    // if it has received any packets:

    if (radio.receiveDone()) // Got one!
    {
        // Print out the information:
        TimeOfWakeup = now; // extend sleep timer
#if defined(USE_SERIAL)
        Serial.print("received from node ");
        Serial.print(radio.SENDERID, DEC);
        Serial.print(", message [");

        // The actual message is contained in the DATA array,
        // and is DATALEN bytes in size:

        for (byte i = 0; i < radio.DATALEN; i++)
            Serial.print((char)radio.DATA[i]);

        // RSSI is the "Receive Signal Strength Indicator",
        // smaller numbers mean higher power.

        Serial.print("], RSSI ");
        Serial.println(radio.RSSI);
#endif
        // RFM69 ensures trailing zero byte, unless buffer is full...so
        radio.DATA[sizeof(radio.DATA) - 1] = 0; // ...if buffer is full, ignore last byte
        if (processCommand((const char *)&radio.DATA[0]))
        {
#if defined(USE_SERIAL)
            Serial.println("Received command accepted");
#endif
        }
        if (radio.ACKRequested())
        {
            radio.sendACK();
#if defined(USE_SERIAL)
            Serial.println("ACK sent");
#endif
        }
    }
#endif

    static bool SampledSinceSleep = false;
    if (!SampledSinceSleep)
    {
        SampledSinceSleep = true;

#if defined(USE_TMP102)
#if !defined(SLEEP_TMP102_ONLY)

        sensor0.begin();
        // read temperature data
        float temperature = sensor0.readTempCfromShutdown();
        sensor0.end();

#if defined(USE_SERIAL)
        // Print temperature and alarm state
        Serial.print("Temperature: ");
        Serial.println(temperature);
#endif

        int batt(0);
#if defined(TELEMETER_BATTERY_V)
        // 10K to VCC and (wired on board) 2.7K to ground
        pinMode(BATTERY_PIN, INPUT_PULLUP); // sample the battery
        batt = analogRead(BATTERY_PIN);
        pinMode(BATTERY_PIN, INPUT); // turn off battery drain
#endif
        char sign = '+';
        static char buf[64];
        if (temperature < 0.f){
            temperature = -temperature;
            sign = '-';
        }
        else if (temperature == 0.f)
            sign = ' ';

        int whole = (int)temperature;

        sprintf(buf, "C:%u, B:%d, T:%c%d.%02d", sampleCount++,
            batt,
            sign, whole,
            (int)(100.f * (temperature - whole)));
#if defined(USE_SERIAL)
        Serial.println(buf);
#endif
#if defined(USE_RFM69) && !defined(SLEEP_RFM69_ONLY)
        radio.sendWithRetry(GATEWAY_NODEID, buf, strlen(buf));
#endif
#endif
#elif defined(USE_HIH6130)
        sensor0.begin();
        // read temperature data
        float humidity, temperature;
        unsigned char stat = sensor0.GetReadings(humidity, temperature);
        sensor0.end();

#if defined(USE_SERIAL)
        // Print temperature and alarm state
        Serial.print("Temperature: ");
        Serial.print(temperature);
        Serial.print(" stat: ");
        Serial.print((int)stat);
        Serial.print(" Humidity: ");
        Serial.println(humidity);
#endif

        int batt(0);
#if defined(TELEMETER_BATTERY_V)
        pinMode(BATTERY_PIN, INPUT_PULLUP); // sample the battery
        batt = analogRead(BATTERY_PIN);
        pinMode(BATTERY_PIN, INPUT); // turn off battery drain
#endif
        char sign = '+';
        static char buf[64];
        if (temperature < 0.f){
            temperature = -temperature;
            sign = '-';
        }
        else if (temperature == 0.f)
            sign = ' ';

        int whole = (int)temperature;
        int wholeRh = (int) humidity;

        sprintf(buf, "C:%u, B:%d, T:%c%d.%02d R:%d.%02d", sampleCount++,
            batt,
            sign, whole,
            (int)(100.f * (temperature - whole)),
            wholeRh,
            (int)(100.f * (humidity - wholeRh)));
#if defined(USE_SERIAL)
        Serial.println(buf);
#endif
#if defined(USE_RFM69) && !defined(SLEEP_RFM69_ONLY)
        radio.sendWithRetry(GATEWAY_NODEID, buf, strlen(buf));
#endif
#endif
    }

    if (now - TimeOfWakeup > ListenAfterTransmitMsec)
    {
        SleepTilNextSample();
        SampledSinceSleep = false;
        TimeOfWakeup = millis();
        ListenAfterTransmitMsec = NormalListenAfterTransmit;
    }
}

#if !defined(SLEEP_WITH_TIMER2)
void sleepPinInterrupt()    // requires 1uF and 10M between two pins
{
    detachInterrupt(digitalPinToInterrupt(TIMER_RC_PIN));
}
#else
ISR(TIMER2_OVF_vect) {} // do nothing but wake up
#endif

namespace {
    unsigned SleepTilNextSample()
    {

#if defined(USE_SERIAL)
        Serial.print("sleep for ");
        Serial.println(SleepLoopTimerCount);
        Serial.end();// wait for finish and turn off pins before sleep
        pinMode(0, INPUT); // Arduino libraries have a symbolic definition for Serial pins?
        pinMode(1, INPUT);
#endif

#if defined(USE_RFM69) && !defined(SLEEP_RFM69_ONLY)
        radio.SPIoff();
#endif

#if defined(TELEMETER_BATTERY_V)
        analogReference(EXTERNAL); // This sequence drops idle current by 30uA
        analogRead(BATTERY_PIN); // doesn't shut down the band gap until we USE ADC
#endif

        // sleep mode power supply current measurements indicate this appears to be redundant
        power_all_disable(); // turn off everything

        unsigned count = 0;

#if !defined(SLEEP_WITH_TIMER2)
        // this requires 1uF and 10M in parallel between pins 3 & 4
        while (count < SleepLoopTimerCount)
        {
            power_timer0_enable(); // delay() requires this
            pinMode(TIMER_RC_PIN, OUTPUT);
            digitalWrite(TIMER_RC_PIN, HIGH);
            delay(10); // Charge the 1uF
            cli();
            power_timer0_disable(); // timer0 powered down again
            attachInterrupt(digitalPinToInterrupt(TIMER_RC_PIN), sleepPinInterrupt, LOW);
            set_sleep_mode(SLEEP_MODE_PWR_DOWN);
            pinMode(TIMER_RC_PIN, INPUT);
            sleep_enable();
            sleep_bod_disable();
            sei();
            sleep_cpu(); // about 300uA, average. About 200uA and rises as cap discharges
            sleep_disable();
            sei();
            count += 1;
        }

#else
        // this section requires no external hardware, AND has a predictable
        // sleep time. BUT takes an extra 100 to 200 uA of sleep current
        power_timer2_enable(); // need this one timer
        clock_prescale_set(clock_div_256); // slow CPU clock down by 256
        while (count < SleepLoopTimerCount)
        {
            cli();
            // This code inspired by:
            // http://donalmorrissey.blogspot.com/2011/11/sleeping-arduino-part-4-wake-up-via.html
            // ...except that we use TIMER2 instead of TIMER1 so we can go to SLEEP_MODE_PWR_SAVE
            // instead of SLEEP_MODE_IDLE
            //
            // We use clock_prescale_set here (not in the link above) to make up for the fact
            // that TIMER2 is only 8 bits wide (TIMER1 is 16)
            //

            /* Normal timer operation.*/
            TCCR2A = 0x00;

            /* Clear the timer counter register.
             * You can pre-load this register with a value in order to
             * reduce the timeout period, say if you wanted to wake up
             * ever 4.0 seconds exactly.
             */
            TCNT2 = 0x0000;

            /* Configure the prescaler for 1:1024, giving us a
             * timeout of 1024 * 256 / 8000000 = 32.768 msec
             */
            TCCR2B = 0x07; // 1024 prescale

            /* Enable the timer overlow interrupt. */
            TIMSK2 = 0x01;
            TIFR2 = 1; // Clear any current overflow flag

            set_sleep_mode(SLEEP_MODE_PWR_SAVE);
            sleep_enable();
            sleep_bod_disable();
            sei();
            sleep_cpu();    // 280 uA -- steady without RFM69
            sleep_disable();
            sei();
            count += 1;
        }
        clock_prescale_set(clock_div_1);
#endif

        power_all_enable();

#if defined(TELEMETER_BATTERY_V)
        ResetAnalogReference();
#endif


#if defined(USE_SERIAL)
        Serial.begin(9600);
        Serial.print(count, DEC);
        Serial.println(" wakeup");
#endif

#if defined(USE_RFM69) && !defined(SLEEP_RFM69_ONLY)
        radio.SPIon();
#endif

        return count;
    }

#if defined(TELEMETER_BATTERY_V)
    void ResetAnalogReference()
    {
        analogReference(INTERNAL);
        pinMode(BATTERY_PIN, INPUT);
        analogRead(BATTERY_PIN);
        delay(10); // let ADC settle
    }
#endif
}
