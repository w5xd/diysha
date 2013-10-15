#include <iostream>
#include <cstdlib>
#include <sstream>
#include <string>
#include <cstring>
#include <map>
#include <ios>
#include <boost/date_time/posix_time/posix_time.hpp>

#include "weather_gov.h"

static const char PCSENSOR_TAG[] = "*** pcsensor ***";
static const char SANDPOINT_TAG[] = "*** sandpoint airport ***";
static const int NUM_FURNACE_TEMPERATURE_CHANNELS = 3;
static const int NUM_FURNACE_TEMPERATURE_FETCHES = 1;
static const char * const FURNACE_CGI_TAG[NUM_FURNACE_TEMPERATURE_FETCHES] = {"*** furnace.cgi ***",
//                                               "*** furnace2.cgi ***",
//                                               "*** furnace3.cgi ***",
//                                               "*** furnace4.cgi ***",
//                                                "*** furnace5.cgi ***"
};
static const char TEMPERATURES_TAG[] = "<h3>Temperatures</h3>";
static const int MAX_NOAA_DATA_OLDNESS_SECONDS = 6000;

/* std::cin is assumed to be the stdout of the combine_inputs script
** That script does this:
** A line with PCSENSOR_TAG
** output of pcsensor program
** A line with SANDPOINT_TAG
** output of getReportedTemp script
** A line with FURNACE_CGI_TAG
** output of furnace.cgi on the furnace controller.
**
** Our std::cout is a single line.
** We append N temperatures in Farenheit to the incoming pcsensor line
** If getReportedTemp has a good line, we add it. Otherwise add -99 or -98
**
** The output of the furnace controller:
** There are four temperatures (as hex-coded ADC results)
** and there are 4 thermostat control wires:  W, Y, G, O
** We are going to ignore the thermostat control wire status because
** procEventLog picks them up.
*/

enum {COLUMN_FAHRENHEIGHT, COLUMN_CELSIUS, COLUMN_RESISTANCE, NUM_COLUMNS};
// copy/paste from the Honeywell documentation
static const float C7089UCoefficients[][NUM_COLUMNS]=
{
    {-20,-28.9,106926}, // 0x383 on the ADC
    {-18,-27.8,100923},
    {-16,-26.7,95310},
    {-14,-25.6,90058},
    {-12,-24.4,85124},
    {-10,-23.3,80485},
    {-8,-22.2,76137},
    {-6,-21.1,72060},
    {-4,-20.0,68237},
    {-2,-18.9,64631},
    {0,-17.8,61246},
    {2,-16.7,58066},
    {4,-15.6,55077},
    {6,-14.4,53358},
    {8,-13.3,49598},
    {10,-12.2,47092},
    {12,-11.1,44732},
    {14,-10.0,42506},
    {16,-8.9,40394},
    {18,-7.8,38400},
    {20,-6.7,36519},
    {22,-5.6,34743},
    {24,-4.4,33063},
    {26,-3.3,31475},
    {28,-2.2,29975},
    {30,-1.1,28558},
    {32,0.0,27219},
    {34,1.1,25949},
    {36,2.2,24749},
    {38,3.3,23613},
    {40,4.4,22537},
    {42,5.6,21516},
    {44,6.7,20546},
    {46,7.8,19626},
    {48,8.9,18754},
    {50,10.0,17926},
    {52,11.1,17136},
    {54,12.2,16387},
    {56,13.3,15675},
    {58,14.4,14999},
    {60,15.6,14356},
    {62,16.7,13743},
    {64,17.8,13161},
    {66,18.9,12607},
    {68,20.0,12081}, // with 12.1K series resistor, this is the middle of our ADC range 0x200
    {70,21.1,11578},
    {72,22.2,11100},
    {74,23.3,10644},
    {76,24.4,10210},
    {78,25.6,9795},
    {80,26.7,9398},
    {82,27.8,9020},
    {84,28.9,8659},
    {86,30.0,8315},
    {88,31.1,7986},
    {90,32.2,7672},
    {92,33.3,7372},
    {94,34.4,7086},
    {96,35.6,6813},
    {98,36.7,6551},
    {100,37.8,6301},
    {102,38.9,6062},
    {104,40.0,5834},
    {106,41.1,5614},
    {108,42.2,5404},
    {110,43.3,5203},
    {112,44.4,5010},
    {114,45.6,4826},
    {116,46.7,4649},
    {118,47.8,4479},
    {120,48.9,4317}, // 0x10D
};

int main(int argc, char* argv[])
{
    enum {START, PCSENSOR, SANDPOINT_AIRPORT_TAG, SANDPOINT_AIRPORT_LINE, 
        FURNACE_CGI, FURNACE_HTML, TEMPERATURES, FINISHED} parseState = START;

    int whichFurnaceCgi = 0;

    if ((argc < 1) || (argc > 1))
    {
        std::cerr << "Usage: procFurnace" << std::endl;
        return 1;
    }

    // fill in lookup table from documented behavior of C7089 device
    std::map<float, float> C7089Map;
    for (int i = 0; i < sizeof(C7089UCoefficients)/sizeof(C7089UCoefficients[0]); i++)
        C7089Map[C7089UCoefficients[i][COLUMN_RESISTANCE]] = 
            C7089UCoefficients[i][COLUMN_FAHRENHEIGHT];

    std::string inputLine;
    std::ostringstream streamToOutput;
    std::string pcsensorLine;
    int whichChannel = 1;
    int ret = 1;
    double adcValues[NUM_FURNACE_TEMPERATURE_CHANNELS];
    memset(&adcValues[0], 0, sizeof(adcValues));
    int adcSamples[NUM_FURNACE_TEMPERATURE_CHANNELS];
    memset(&adcSamples[0], 0, sizeof(adcSamples));
    while (std::getline(std::cin, inputLine))
    {
        switch (parseState)
        {
        case START:
            if (inputLine.find(PCSENSOR_TAG) != inputLine.npos)
                parseState = PCSENSOR;
            break;

        case PCSENSOR:  // input from the USB temperature sensor
            if (inputLine.find("Temperature(F)") != inputLine.npos)
            {
                streamToOutput << inputLine;
                pcsensorLine = inputLine;
                parseState = SANDPOINT_AIRPORT_TAG;
            }
            else
            {
                ret = 2;
                parseState = FINISHED;  // error
            }
            break;

        case SANDPOINT_AIRPORT_TAG:
            if (inputLine.find(SANDPOINT_TAG) != inputLine.npos)
                parseState = SANDPOINT_AIRPORT_LINE;
            break;

        case SANDPOINT_AIRPORT_LINE:    // input from NOAA.gov
            {
                WeatherGov gv(inputLine);
                std::string airportTemp = gv.airportTemp();
                if (!gv.airportTime().is_not_a_date_time())
                {
                    boost::posix_time::ptime now = boost::posix_time::second_clock::universal_time();
                    boost::posix_time::time_duration diff = now - gv.airportTime();
                    boost::posix_time::time_duration::sec_type dataOldnessSeconds = diff.total_seconds();

                    if (dataOldnessSeconds >= MAX_NOAA_DATA_OLDNESS_SECONDS )
                    {
                        airportTemp = "-95";
                        std::cerr << now << " procFurnace: old noaa data: " << dataOldnessSeconds << " " << gv.timeStamp() << std::endl;
                    }
                }

                streamToOutput << "\t" << airportTemp;
                pcsensorLine += std::string("\t") + airportTemp;
            }
            parseState = FURNACE_CGI;
            break;

        case FURNACE_CGI:
            if (inputLine.find(FURNACE_CGI_TAG[whichFurnaceCgi]) != inputLine.npos)
                parseState = FURNACE_HTML;
            break;

        case FURNACE_HTML:
            if (inputLine.find(TEMPERATURES_TAG) != inputLine.npos)
                parseState = TEMPERATURES;
            break;

        case TEMPERATURES:
            if (inputLine.find("<br/>") != inputLine.npos)
            {   int channelIndex = whichChannel - 1;
                double result = ::strtol(inputLine.c_str(), 0, 16);
                result /= 4;	//As of lastest rev, it gives results times 4
                if ((result >= 0.0) && (result <= 1023.0))
                {
                    adcValues[channelIndex] +=  result;
                    adcSamples[channelIndex] += 1;
                }

                if (whichFurnaceCgi == NUM_FURNACE_TEMPERATURE_FETCHES-1)   // last time
                {
                    double temperatureF = -98.0;
                    // result is in the range of 0.0 to 1023.0, which correspond to 0.0V and 5.0V
                    if (adcSamples[channelIndex] == 0)
                        temperatureF = -99;
                    else
                    {
                        result = static_cast<double>(adcValues[channelIndex]) / adcSamples[channelIndex];
                        if (adcSamples[channelIndex] != NUM_FURNACE_TEMPERATURE_FETCHES)
                            std::cerr << " procFurnace partial data. channel: " << whichChannel << " samps: " << adcSamples[channelIndex] << std::endl;
                        switch (whichChannel)
                        {
                        case 2: case 3: case 4:
                            // LM235 sensor. answer is 10mV/K
                            result *= 500.0/1024.0; // Kelvins
                            result -= 273.15; // Celsius
                            result *= 1.8; result += 32; // Fahrenheit
                            temperatureF = result;
                            break;

                        case 1: 
                            {
                                // Honeywell C7089U outdoor sensor
                                static const double R0 = 12100.0; // series resistor to 5VDC Vcc.
                                double Routside = (R0 * result)/(1024.0 - result);
                                std::map<float, float>::iterator itor = C7089Map.upper_bound(Routside);
                                if (itor==C7089Map.end())
                                    temperatureF = -21.0;
                                else if (itor == C7089Map.begin())
                                    temperatureF = 121.0;
                                else
                                {
                                    // linear extrapolation between the two table entries
                                    std::map<float,float>::iterator prev = itor; prev--;
                                    float thisR = itor->first; float prevR = prev->first;
                                    float thisT = itor->second; float prevT = prev->second;
                                    temperatureF = thisT + 
                                        (prevT - thisT) * (Routside - thisR)/(prevR - thisR);
                                }
                            }
                            break;
                        default:
                            break;
                        }
                    }
                    streamToOutput.unsetf(std::ios::floatfield);
                    streamToOutput.precision(4);
                    streamToOutput << '\t' << temperatureF;
                    if (whichChannel == NUM_FURNACE_TEMPERATURE_CHANNELS)
                    {
                        std::cout << streamToOutput.str() << std::endl;
                        ret = 0;
                    }
                }
                if (whichChannel == NUM_FURNACE_TEMPERATURE_CHANNELS)
                {
                    if (++whichFurnaceCgi >= NUM_FURNACE_TEMPERATURE_FETCHES)
                        parseState = FINISHED;
                    else
                        parseState = FURNACE_CGI;
                    whichChannel = 1;
                    break;
                }
                else
                    whichChannel += 1;
            }
            break;
        default:
            break;
        }
    }
    if ((ret != 0) && !pcsensorLine.empty())
        std::cerr << pcsensorLine << std::endl;
    return ret;
}

