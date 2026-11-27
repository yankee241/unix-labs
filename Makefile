all: hardlinks

hardlinks: hardlinks.cpp
	g++ -std=c++17 -Wall -Wextra -pedantic -O2 -o hardlinks hardlinks.cpp -lcrypto

clean:
	rm -f hardlinks
