#ifndef WEATHER_GOV_H
#define WEATHER_GOV_H

#include <string>
#include <boost/date_time/posix_time/posix_time.hpp>
#include <boost/algorithm/string.hpp>

static const char FAHRENHEIT[] = "Fahrenheit";
static const char * const MONTHS[12] = 
{
	"jan", "feb", "mar", "apr", "may", "jun",
	"jul", "aug", "sep", "oct", "nov", "dec"
};

/* WeatherGov
** Class to parse the result of getReportedTemp from weather.gov
** And turn it into a time and a temperature in various formats.
*/
class WeatherGov
{
public:
    WeatherGov(const std::string &inputLine):m_airportTemp("-99")
    {
        int FahrenheitPos = inputLine.find(FAHRENHEIT);
        if (FahrenheitPos != inputLine.npos)
        {
            // Check that the time stamp is acceptably recent
            m_timeStamp = inputLine.substr(FahrenheitPos + sizeof(FAHRENHEIT));
            if (m_timeStamp.length() > 0)
            {   
                /* of the form:
                ** Sun, 19 Aug 2012 19:55:00 -0600 
                */
                int year = -1;
                int month = -1;
                int day = -1;
                int hour = -1;
                int minute = -1;
                int seconds = -1;
                int hoursOffset = -1;
                int hrsParseSign = 0;
                int hrsDigits = 0;
                int minutesOffset = -1;

                int curVal = 0;
                for (const char *p = m_timeStamp.c_str(); *p; p++)
                {
                    if (isdigit(*p)) {curVal *= 10; curVal += *p - '0';}
                    if ((day < 0) && isspace(p[1]) && (curVal > 0))
                    {day = curVal; curVal = 0;   }
                    else if ((month < 0) && !isspace(*p))
                    {
                        std::string mo = std::string(p).substr(0, 3);
                        boost::algorithm::to_lower(mo);
                        for (int j = 0; j < 12; j++)
                        {
                            if (mo == std::string(MONTHS[j]))
                            {
                                month = 1 + j;
                                p += 3;
                                break;
                            }
                        }
                    }
                    else if (year < 0) {if ( isspace(p[1]) )
                    {year = curVal; curVal = 0;}}
                    else if (hour < 0) {if  (p[1] == ':') 
                    {	hour = curVal; curVal = 0; }}
                    else if (minute < 0) { if (p[1] == ':')
                    { minute = curVal; curVal = 0;}}
                    else if (seconds < 0) { if (isspace(p[1]))
                    { seconds = curVal; curVal = 0;}}
                    else if (hrsParseSign == 0) { if (!isspace(*p))
                    {
                        if (*p == '-') hrsParseSign = -1;
                        else hrsParseSign = 1;
                        if (isdigit(*p)) hrsDigits += 1;
                    }}
                    else if (hoursOffset < 0) {if (isdigit(*p) && (++hrsDigits == 2))
                    {
                        hoursOffset = curVal; curVal = 0;
                    }}
                    else minutesOffset = curVal;
                }

                if ((hrsDigits == 2) && (hoursOffset >= 0) && (minutesOffset >= 0))
                {

                    boost::posix_time::time_duration tzOffset(hoursOffset*hrsParseSign,minutesOffset,0);
                    boost::gregorian::date reportedDate(year, month, day);
                    boost::posix_time::ptime reportedTime(reportedDate, 
                        boost::posix_time::time_duration(hour, minute,seconds));

                    reportedTime -= tzOffset;   // convert report to universal time
                    m_airportTime = reportedTime;
                    extractTemperature(inputLine);
                }
                else
                    m_airportTemp = "-96";
            }
            else
                m_airportTemp = "-98";
        }
    }
    ~WeatherGov(){}

    const boost::posix_time::ptime &airportTime()const
    {        return m_airportTime; }

    const std::string &airportTemp() const
        // "-99" means couldn't parse, -98 means timeStamp was not 25 characters, 
        //  -97 means the temperature digits were not as expected
        // -96 means we failed parsing the time-of-day stamp
    {       return m_airportTemp;} 

    const std::string &timeStamp() const
    {        return m_timeStamp;    }


private:
    std::string m_airportTemp;
    boost::posix_time::ptime m_airportTime;
    std::string m_timeStamp;
    void extractTemperature(const std::string &inputLine)
    {
        int pos = strspn(inputLine.c_str(), "0123456789-+");
        if (pos > 0)
            m_airportTemp = inputLine.substr(0, pos);
        else
            m_airportTemp = "-97";
    }
};


#endif
