#include <iostream>
#include <sstream>
#include <string>
#include <ios>
#include <boost/date_time/posix_time/posix_time.hpp>
#include <boost/date_time/c_local_time_adjustor.hpp>

#include "weather_gov.h"

/* std::cin is assumed to be the stdout of the getReportedTemp script
** This is more a testing script than a production script.
** In normal furnace operations, the airport input data is polled
** on the furnace polling loop (poll_furnace).
** This script outputs the getReportedTemp results in a way
** than can be plotted in gnuplot with the same time format
** as the other hvac scripts.
*/

int main(int argc, char* argv[])
{
    if ((argc < 1) || (argc > 1))
    {
        std::cerr << "Usage: procWeatherGov" << std::endl;
        return 1;
    }

    boost::posix_time::time_facet *facet =
    new boost::posix_time::time_facet("%Y/%m/%d %H:%M:%S");
    std::ostringstream date_ss;
    date_ss.imbue(std::locale(date_ss.getloc(), facet));

    std::string inputLine;
    std::ostringstream streamToOutput;

    boost::posix_time::ptime previousTime;

    while (std::getline(std::cin, inputLine))
    {
        WeatherGov gv(inputLine);
        std::string airportTemp = gv.airportTemp();
        if (!gv.airportTime().is_not_a_date_time())
        {
            boost::posix_time::time_duration::sec_type dataOldnessSeconds = 1;
            if (!previousTime.is_not_a_date_time())
            {
                boost::posix_time::time_duration diff = gv.airportTime() - previousTime;
                dataOldnessSeconds = diff.total_seconds();
            }
            if (dataOldnessSeconds != 0)
            {
                date_ss.str("");
                date_ss << boost::date_time::c_local_adjustor<boost::posix_time::ptime>::utc_to_local(gv.airportTime());
                std::cout << date_ss.str() << '\t' << gv.airportTemp() << '\t' << dataOldnessSeconds << std::endl;
                previousTime = gv.airportTime();
            }
        }
    }
    return 0;
}

