#include <iostream>
#include <string>
#include <cstdlib>

/*
** Program to read from stdin (expecting to be piped from curl)
** Writes the first part of a multi-part MIME to its stdout (which is what 
** the program "motion" puts on its web page as a jpeg file).
** The result at stdout should be a valid jpg file as acquired from motion.
*/

extern "C" int main(int argc, char **argv)
{
	enum {BOUNDARY, CONTENT_LENGTH, DATA} state = BOUNDARY;
        int boundaryIdx = 0;
        std::string header;
	// arbitrary limits to keep program from running forever.
        static const int MaxCharsPerLine = 256;
	static const int MaxHeaders = 100;
        static const char *BoundaryString = "--BoundaryString\r\n";
	int numHeaders = 0;
        int contentLength = 0;
	int readLength = 0;
        char prevChar = 0;
        while (!std::cin.eof())
        {
		char c = std::cin.get();
		switch (state)
		{
		case BOUNDARY:
                        if (c != BoundaryString[boundaryIdx])
			{
				std::cerr << "No --BoundaryString found" << std::endl;
				return 1;
			}
			boundaryIdx += 1;
			if (!BoundaryString[boundaryIdx])
			{
				state = CONTENT_LENGTH;
				continue;
			}
			break;
		case CONTENT_LENGTH:
                        header += c;
			if ((c == '\n') && (prevChar == '\r'))
			{
				if (header.substr(0,15) == "Content-Length:")
				{
					contentLength = atoi(header.c_str() + 15);
				}
				if (header.length()==2) // \r\n header....
				{
					if (contentLength == 0)
					{
						std::cerr << "Can't accept zero content-length" << std::endl;
						return 1;
					}
					state = DATA;
					continue;
				}
				if (++numHeaders >= MaxHeaders)
				{
					std::cerr << "Too many headers: " << numHeaders << std::endl;
					return 1;
				}
				header.clear();
			}
			prevChar = c;
                        if (header.length() >= MaxCharsPerLine)
			{
				std::cerr << "Header too long: " << header.length() << std::endl;
				return 1;
			}
			break;
		case DATA:
	                std::cout.put(c);
			readLength += 1;
			if (readLength == contentLength)
				return 0;
			break;
		}
        }
	std::cerr << "Not enough input data" << std::endl;
	return 1;
}
