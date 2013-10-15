#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <boost/filesystem.hpp>
#include <boost/date_time/posix_time/posix_time.hpp>
#include <boost/date_time/c_local_time_adjustor.hpp>

/*
** Requires BOOST version 1.46.1 or later
*/

typedef std::map<std::string, std::string> map_t;

class Json
{
public:
    Json() : m_readState(START), m_depth(0)
    {
    }
    void nextChar(char c)
    {
        switch (m_readState)
        {
        case START:
            if (c == '{')
                m_readState += 1;
            break;
        case BEGINTAG:	
            if (c ==  '"')
            {
                m_readState += 1;
                sbTag.clear();
                sbValue.clear();
            }
            break;
        case ENDTAG:
            if (c == '"')
                m_readState += 1;
            else
                sbTag += c;
            break;
        case VALUE_SEPARATOR:
            if (c == ':')
                m_readState += 1;
            break;
        case VALUE_END:
            if ((c == ',') || (c == '}'))
            {
                m_map[sbTag] = sbValue;
                m_readState = BEGINTAG;
            }
            else
            {
                sbValue += c;
                if (c == '{')
                {
                    m_readState = BRACE;
                    m_depth++;
                }
                else if (c == '[')
                {
                    m_depth++;
                    m_readState = BRACKET;
                }
            }
            break;
        case BRACE:
            sbValue += c;
            if (c == '{')
                m_depth++;
            else if ((c == '}') && (--m_depth==0))
            {
                m_readState = BEGINTAG;
                m_map[sbTag] = sbValue;
            }
            break;
        case BRACKET:
            sbValue += c;
            if (c == '[')
                m_depth++;
            else if ((c == ']') && (--m_depth == 0))
            {
                m_readState = BEGINTAG;
                m_map[sbTag] = sbValue;
            }
            break;
        }
    }

    const map_t &getMap() const
    {
        return m_map;
    }

    static void getArray(const std::string &s, 
        std::vector<std::string> &v)
    {
        if ((s.length() > 0) && (s[0] == '['))
        {
            int depth = 0;
            std::string sb;
            for (int i = 1; i < s.length(); i++)
            {
                char c = s[i];
                if (depth == 0)
                {
                    if ((c == ',') || (c == ']'))
                    {
                        v.push_back(sb);
                        sb.clear();
                    }
                    else
                        sb += c;
                    if (c == '[')
                        depth += 1;
                }
                else if (c == ']')
                {
                    depth -= 1;
                    sb += c;
                }
                else if (c == '[')
                {
                    depth += 1;
                    sb += c;
                }
                else sb += c;
            }
        }
    }

private:

    enum {START = 0,
        BEGINTAG = 1,
        ENDTAG = 2,
        VALUE_SEPARATOR = 3,
        VALUE_END = 4,
        BRACE = 5,
        BRACKET = 6};

    int m_readState;
    int m_depth;
    std::string sbTag;
    std::string sbValue;

    map_t m_map;
};

static const char * const Columns[] =
{"hour", "minute", "relay", "temp", "ttemp", "humidity"};
// must be same order as Columns 
enum {HOUR, MINUTE, RELAY, TEMPERATURE, TARGET_TEMPERATURE, HUMIDITY, NUM_COLUMNS};

class Event
{
public:
    enum {O_BIT=0x100, B_BIT=0x40, G_BIT = 0X20, Y_BIT=0X8, W_BIT=0X2};
    Event(const char *relay, const char *temp, const char *ttemp, const char *humidity, const std::string &fname)
        : m_fname(fname)
    {
        m_relay = atoi(relay);
        m_temperature = (float)atof(temp);
        m_humidity = (float)atof(humidity);
        m_targetTemperature = atoi(ttemp);
    }
    Event() : m_relay(0), m_temperature(0), m_targetTemperature(0), m_humidity(0){}
    std::string relay()const{
        std::string ret;
        ret += m_relay & O_BIT ? '0' : '-';
        ret += m_relay & B_BIT ? 'B' : '-';
        ret += m_relay & G_BIT ? 'G' : '-';
        ret += m_relay & Y_BIT ? 'Y' : '-';
        ret += m_relay & W_BIT ? 'W' : '-';
        return ret;
    }
    int relayCoded()const{
        if (m_relay & W_BIT) return 2; // furnace
        else if ((m_relay & (Y_BIT|B_BIT)) == (Y_BIT|B_BIT)) return 3; // heatpump
        else if (m_relay & Y_BIT) return 4; // cooling
        else if (m_relay & G_BIT) return 1; // fan-only
        return 0;
    }
    int target()const{return m_targetTemperature;}
    float temperature()const{return m_temperature;}
    float humidity()const{return m_humidity;}
    const std::string &filename()const{return m_fname;}
protected:
    int m_relay;
    float m_temperature;
    int m_targetTemperature;
    float m_humidity;
    std::string m_fname;
};

typedef std::map<boost::posix_time::ptime, Event> result_t;

class StatusReport
{
public:
    StatusReport(const std::string &fname) : 
      m_fname(fname), m_haveNamedFile(false)
    {    }

    void report(const std::string &msg)
    {
        if (!m_haveNamedFile)
            std::cout << "processing " << m_fname << std::endl;
        m_haveNamedFile = true;
        std::cout << msg << std::endl;
    }

protected:
    const std::string m_fname;
    bool m_haveNamedFile;
};

static void processFile(const boost::filesystem::path &path, int hrsOffset, result_t &results)
{
    std::string fn = path.string();
    std::time_t t = boost::filesystem::last_write_time(path);

    boost::posix_time::ptime lwt = boost::posix_time::from_time_t(t);
    lwt = boost::date_time::c_local_adjustor<boost::posix_time::ptime>::utc_to_local(lwt);
    lwt += boost::posix_time::time_duration(hrsOffset, 0, 0, 0);

    StatusReport statusReport(fn);

    std::ifstream in(fn.c_str());
    Json json;
    while (!in.eof())
    {
        char c;
        in.get(c);
        json.nextChar(c);
    }

    map_t::const_iterator itor = json.getMap().find("eventlog");
    if (itor != json.getMap().end())
    {
        std::vector<std::string> v;
        json.getArray(itor->second, v);
        if (v.size() > 1) 
        {   // more than just labels
            std::vector<std::string> labels;
            json.getArray(v[0], labels);
            std::map<int, int> colMap;
            for (int j = 0; j < (int)NUM_COLUMNS; j++)
            {
                std::string l; l += '"'; l += Columns[j]; l += '"';
                for (int k = 0; k < labels.size(); k++)
                {
                    if (labels[k] == l)
                        colMap[j] = k;
                }
            }
            if (colMap.size() == (int)NUM_COLUMNS)
            {   // every column we expect appears?
                for (int i = 1; i < v.size(); i++)
                {
                    std::vector<std::string> vals;
                    json.getArray(v[i], vals);
                    if (vals.size() == labels.size())
                    {   // this record has an entry for every label?
                        boost::posix_time::time_duration todFile = lwt.time_of_day();
                        int todHors = todFile.hours();
                        int todMins = todFile.minutes();
                        int hrs = atoi(vals[colMap[HOUR]].c_str());
                        int min = atoi(vals[colMap[MINUTE]].c_str());
                        boost::posix_time::time_duration tod(hrs, min, 0, 0), delta;
                        delta = tod - todFile;
                        const int minMin = 2;
                        if (delta.total_seconds() > (minMin * 60)) // assume rolled over midnight
                            delta -= boost::posix_time::time_duration(24,0,0,0);
                        long ts = delta.total_seconds();
                        const int maxMin = 120;
                        if ((ts > (minMin * 60)) || (ts < (maxMin * -60)))
                        {
                            std::ostringstream oss;
                            oss << "Time label (" << hrs << ':' << min << ") not in window " << maxMin << "min before file stamp ("
                                << todHors << ':' << todMins << ") ts=" << ts;    
                            statusReport.report(oss.str());
                            continue;
                        }
                        boost::posix_time::ptime tstamp = lwt + delta;
                        results[tstamp] = Event(vals[colMap[RELAY]].c_str(), 
                            vals[colMap[TEMPERATURE]].c_str(),
                            vals[colMap[TARGET_TEMPERATURE]].c_str(), 
                            vals[colMap[HUMIDITY]].c_str(),
                            path.filename().string());
                    }
                }
            }
        }
    }
    else statusReport.report("No eventlog in json");
}

int main(int argc, char* argv[])
{
    std::vector<std::string> args;
    bool appendMode = false;
    int retval = 0;
    for (int i = 0; i < argc; i++)
    {
    	if (strcmp(argv[i], "-a") == 0)
            appendMode = true;
        else
            args.push_back(argv[i]);
    }

    if ((args.size() < 3) || (args.size() > 4))
    {
        std::cout << "Usage: processEventLog [-a] <path> <out> [tz-offset-hours]" << std::endl;
        return 1;
    }
    try
    {

        boost::filesystem::path path(args[1]);
        if (!boost::filesystem::exists(path))
        {
            std::cout << args[1] << " does not exist." << std::endl;
            return 2;
        }

        if (!appendMode && !boost::filesystem::is_directory(path))
        {
            std::cout << args[1] << " must be a directory." << std::endl;
            return 3;
        }

        std::ofstream out(args[2].c_str(), appendMode ? std::ofstream::app : std::ofstream::trunc );
        if (!out.is_open())
        {
            std::cout << "failed to open output file " << args[2] << std::endl;
            return 4;
        }

        int hrsOffset = 0; 
        if (args.size() > 3)
            hrsOffset = atoi(args[3].c_str());

        result_t results;

        if (!appendMode)
        {
            boost::filesystem::directory_iterator end_itr; // default construction yields past-the-end
            for ( boost::filesystem::directory_iterator itr( path );
                itr != end_itr;
                ++itr )
            {
                if ( boost::filesystem::is_directory(itr->status()) )
                {
                    for ( boost::filesystem::directory_iterator itr2( *itr );
                        itr2 != end_itr;
                        ++itr2 )
                    {
                        if (!boost::filesystem::is_regular_file(*itr2))
                            continue;
                        processFile(itr2->path(), hrsOffset, results);
                    }
                }
            }
            out << "DATE\t" << "TIME\t" << "relay" << '\t' << "target"
                 << '\t' << "inside" << '\t' << "humidity" << '\t' << "coded\t" 
                 << "FILE" << std::endl;
        }
        else
            processFile(path, hrsOffset, results);

        boost::posix_time::time_facet *facet =
		new boost::posix_time::time_facet("%Y/%m/%d %H:%M:%S");
        std::ostringstream date_ss;
        date_ss.imbue(std::locale(date_ss.getloc(), facet));
        for (
            result_t::const_iterator resItor = results.begin();
            resItor != results.end();
            resItor++)
        {
            date_ss.str("");
            date_ss << resItor->first;
            const Event &e = resItor->second;
            out << date_ss.str() << "\t" <<
                e.relay() << '\t' <<
                e.target() << '\t' <<
                e.temperature() << '\t' <<
                e.humidity() << '\t' <<
                e.relayCoded() << '\t' <<
                e.filename() <<
                std::endl;
            int insideTemp = (int)(e.temperature() + 0.5);
            if ((insideTemp >= 45) && (insideTemp <= 90))
                retval = insideTemp;
        }

    }
    catch (const std::exception &e)
    {
        std::cout << "Didn't work because " << e.what() << std::endl;
    }
    return retval;
}

