This Arduino sketch implements a wireless thermometer.

The hardware configuration is the combination of the RFM69 wireless module
and TMP102 temperature sensor:
<br/>https://learn.sparkfun.com/tutorials/rfm69hcw-hookup-guide
<br/>https://learn.sparkfun.com/tutorials/tmp102-digital-temperature-sensor-hookup-guide.

HIH6130 support instead of TMP102 is a compile-time option. The 
<a href='https://www.sparkfun.com/products/11295'>HIH6130</a>
has
humidity in addition to temperature, but is limited to -20C to 85C.

The hookups are the same for either sensor: GND, VCC (3.3V), SDA, SCL are the only
pins used. The pin positions on their breakout boards differ.

Of the sleep options available at compile time in this sketch, the best
battery life is obtained with a 10M ohm resistor in parallel with a 1uF
capacitor across digital pins 3 and 4, with the + side of the capacitor on
digital 3. SMD components of size 1206 are easy enough to solder on. The R can
go on one side of the board and the C on the other.
The component values are not critical. A pair of AAA lithium cells
powered one of these for 9 months (and counting) with SetDelayLoopCount 
configured such that updates occur about every 11 minutes. A different unit
configured for 5 minute updates lasted 6 months. AA cells are rated
to twice the capacity of AAA if these battery changes are too frequent.

A 2.7K resistor is added from A0 to ground for the purpose of 
telemetering the battery volatage.
On the Arduinio Mini Pro, 3.3V version, solder jumper SJ1 is removed (which disables
the on-board volatage regulator and LED.)
The system is powered with a 2 cell AAA (or AA) lithium battery wired to VCC (not RAW).

To setup the EEPROM off the air (i.e. with the RFM69 not connected) you must
leave USE_RFM69 undefined because the code that uses the RFM69 but cannot
find it blocks reading from the serial port.

The required SetFrequencyBand settings are documented in RFM69.h (91 in USA)



