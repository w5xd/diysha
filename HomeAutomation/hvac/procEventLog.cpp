#include <iostream>
#include <string>
#include <sstream>
#include <fstream>
#include <vector>
#include <boost/date_time/local_time/local_time.hpp>
#include <boost/date_time/posix_time/posix_time.hpp>

/*
** The furnevt.cgi file on the modtronix controller board is html starting like this:
**
    <html>
    <head>
    </head>
    <body>
    CGI file for polling ior5e board and sbc65 controller for events
    <h3>Events</h3>
    count=%ZFF<br/>
    Times are 10's of seconds back from now.<br/>
    Events follow
    <table>
     <tr><td>%Z00</td><td>%Z80</td></tr>
    ...
    </table>
    <h3>RelayEvents</h3>
    ... as above, but for relay events
...
**
** This program takes the result of the above on std::cin
** and writes a series of logged events to either of two files
** as specified on (required) command line args. 
*
* The return code from this process indicates:
* negative means an error occured.
* zero means no error.
* Write a string indicating number to stdout. The number is
* 32 * number of relay events + number of opto events
*/

static const char htmlTag[] = "<html>";
static const char eventsHeading[] = "<h3>Events</h3>";
static const char relayEventsHeading[] = "<h3>RelayEvents</h3>";
static const char eventCount[] = "count=";
static const char tableTag[] = "<table>";
static const char rowStarts[] = "<tr><td>";
static const char rowEnds[] = "</td></tr>";

class EventEntry
{
public:
    EventEntry(int gtag, int value, int time) : m_time(time), m_value(value), m_globalTag(gtag){}
    int m_globalTag;
    int m_value;
    int m_time;
    std::string prValue(int which) const 
    {
        std::string ret;
        if (m_value == 0) return "-----";
        if (which == 0)
            ret += (m_value & 2) ? "O" : "-";
        else
            ret += (m_value & 16) ? "E" : "-";
        ret += (m_value & 2) ? "-" : "B";
        ret += (m_value & 4) ? "G" : "-";
        ret += (m_value & 1) ? "Y" : "-";
        ret += (m_value & 8) ? "W" : "-";
        return ret;
    }
    std::string codedVal() const
    {
        // W wire means gas heat
        if (m_value & 8) return "2";
        if (m_value & 1)    // compressor on?
            return (m_value & 2) != 0 ? // O wire on?
            "4" : // cooling
            "3";     // heating
        return "0";
    }
};

typedef std::vector<EventEntry> Events_t;

int main(int argc, char* argv[])
{
    if ((argc < 1) || (argc != 3))
    {
        std::cerr << "Usage: processEventLog <optLogFile> <relayLogFile>" << std::endl;
        return -1;
    }

    std::ofstream optLog(argv[1], std::ofstream::app);
    if (!optLog.is_open())
    {
        std::cerr << "Failed to open output " << argv[1] << std::endl;
        return -2;
    }
    std::ofstream rlyLog(argv[2], std::ofstream::app);
    if (!rlyLog.is_open())
    {
        std::cerr << "Failed to open output " << argv[2] << std::endl;
        return -2;
    }

    enum {HTML_TAG=1, EVENTS_HEADING, EVENT_COUNT, EVENTS_TABLE, EVENTS, FINISHED, INVALID_STATE} 
        parseState = HTML_TAG;
    std::string nextLine;
    int which = 0;
    int globalEventCount[2] = {-1, -1};
    Events_t events[2];
    std::ostream *outstream[2] = {&optLog, &rlyLog};
    while (std::getline(std::cin, nextLine))
    {
        switch (parseState)
        {
        case HTML_TAG:
            if (nextLine.find(htmlTag) != nextLine.npos)
                parseState = EVENTS_HEADING;
            break;

        case EVENTS_HEADING:
            if (nextLine.find(eventsHeading) != nextLine.npos)
                parseState = EVENT_COUNT;
            break;

        case EVENT_COUNT:
            {
                int countPos = nextLine.find(eventCount);
                if (countPos != nextLine.npos)
                {
                    globalEventCount[which] = atoi(nextLine.substr(countPos + sizeof(eventCount) - 1).c_str());
                    parseState = EVENTS_TABLE;
                }
            }
            break;

        case EVENTS_TABLE:
            if (nextLine.find(tableTag) != nextLine.npos)
                parseState = EVENTS;
            break;

        case EVENTS:
            {
                int rowStartPos = nextLine.find(rowStarts);
                int rowEndsPos = nextLine.find(rowEnds);
                if ((rowStartPos != nextLine.npos) && (rowEndsPos != nextLine.npos))
                {
                    int tdEndTag1 = nextLine.find("</td>");
                    if (tdEndTag1 < rowEndsPos)
                    {   // need two </td>'s on the row
                        int secondTdTag = nextLine.find("<td>",tdEndTag1);
                        if (secondTdTag != nextLine.npos)
                        {
                            int start = rowStartPos+sizeof(rowStarts) - 1;
                            std::string td1 = nextLine.substr(start, tdEndTag1 - start);
                            std::string td2 = nextLine.substr(secondTdTag + 4, rowEndsPos - secondTdTag - 4);
                            if (td1.empty() || td2.empty())
                                parseState = FINISHED;
                            else
                            {
                                events[which].push_back(
                                    EventEntry(globalEventCount[which]--, atoi(td1.c_str()), atoi(td2.c_str()))
                                    );
                            }
                        }
                        else
                            parseState = FINISHED;  // was no second <td> tag
                    }
                    else
                    {
                        // don't try to do any more parsing of this file
                        parseState = FINISHED;
                    }
                }
            }
            break;

        case FINISHED:
            if ((which == 0) && (nextLine.find(relayEventsHeading) != nextLine.npos))
            {   
                which = 1;
                parseState = EVENT_COUNT;  
            }
        case INVALID_STATE:
            break;  // read to end of std::cin

        default:    // don't read to end of std::cin. Software bug here.
            return -1 -(int)INVALID_STATE;  // invalid state
        }
    }
    if ((parseState == FINISHED) || (parseState == EVENTS))
    {   // time stamp the events assuming it took zero time to transfer them from the modtronix board
        boost::posix_time::time_facet *facet =
		new boost::posix_time::time_facet("%Y/%m/%d %H:%M:%S");
        std::ostringstream date_ss;
        date_ss.imbue(std::locale(date_ss.getloc(), facet));
        
        boost::posix_time::ptime now = boost::posix_time::second_clock::local_time();
        for (which = 0; which <= 1; which++)
        {
            for (Events_t::const_reverse_iterator itor = events[which].rbegin(); itor != events[which].rend(); itor++)
            {
                date_ss.str("");
                boost::posix_time::time_duration    diff(0, 0, itor->m_time * 10);
                date_ss << (now-diff);
                *outstream[which] << itor->m_globalTag << "\t" << 
                    date_ss.str() << "\t" << itor->prValue(which) << 
                    "\t" << itor->codedVal() << std::endl;
            }
        }
        std::cout << events[0].size() + (events[1].size() * 32) << std::endl;
        return 0;
    }
    else
        return -(int)parseState;
}

