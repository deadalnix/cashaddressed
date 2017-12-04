module util.base32;

/*********************
 * Encoding routines.
 ********************/

/**
 * Find out the size of the string in base32 given the size
 * of the data to encode.
 */
size_t getBase32Size(size_t length) {
	if (length == 0) {
		return 0;
	}
	
	return ((length * 8  - 1) / 5) + 1;
}

size_t encode(
	bool discardPartial = false,
)(const(ubyte)[] data, ubyte[] buffer) in {
	assert(buffer.length >= getBase32Size(data.length));
} body {
	return encode!(c => char(c & 0x1f), discardPartial)(
		data,
		*(cast(char[]*) &buffer),
	);
}

size_t encode(
	alias encodeChar,
	bool discardPartial = false,
)(const(ubyte)[] data, char[] buffer) in {
	assert(buffer.length >= getBase32Size(data.length));
} body {
	size_t i;
	
	void putChar(uint n) {
		buffer[i++] = encodeChar(n & 0x1f);
	}
	
	while (data.length >= 5) {
		scope(success) data = data[5 .. $];
		
		uint b0 = *(cast(uint*) data.ptr);
		uint b1 = *(cast(uint*) (data.ptr + 1));
		
		// Only required on little endian.
		import core.bitop;
		b0 = bswap(b0);
		b1 = bswap(b1);
		
		putChar(b0 >> 27);
		putChar(b0 >> 22);
		putChar(b0 >> 17);
		putChar(b0 >> 12);
		putChar(b1 >> 15);
		putChar(b1 >> 10);
		putChar(b1 >> 5);
		putChar(b1);
	}
	
	// We got a multiple of 5 number of bits to encode, bail early.
	if (data.length == 0) {
		return i;
	}
	
	ubyte[7] suffixBuffer;
	ubyte[] suffix;
	switch(data.length) {
		case 1:
			suffix = suffixBuffer[0 .. 2];
			suffix[1] = cast(ubyte) (data[0] << 2);
			goto Next1;
		
		case 2:
			suffix = suffixBuffer[0 .. 4];
			suffix[3] = cast(ubyte) (data[1] << 4);
			goto Next2;
		
		case 3:
			suffix = suffixBuffer[0 .. 5];
			suffix[4] = cast(ubyte) (data[2] << 1);
			goto Next3;
		
		case 4:
			suffix = suffixBuffer[0 .. 7];
			suffix[6] = cast(ubyte) (data[3] << 3);
			suffix[5] = cast(ubyte) (data[3] >> 2);
			suffix[4] = cast(ubyte) (data[2] << 1 | data[3] >> 7);
			goto Next3;
		
		Next3:
			suffix[3] = cast(ubyte) (data[1] << 4 | data[2] >> 4);
			goto Next2;
		
		Next2:
			suffix[2] = cast(ubyte) (data[1] >> 1);
			suffix[1] = cast(ubyte) (data[0] << 2 | data[1] >> 6);
			goto Next1;
		
		Next1:
			suffix[0] = cast(ubyte) (data[0] >> 3);
			break;
		
		default:
			assert(0);
	}
	
	static if (discardPartial) {
		suffix = suffix[0 .. $ - 1];
	}
	
	/**
	 * We run the actual encoding at the end to make sure
	 * getChar calls are made in order. This allow various
	 * checksum computation to be backed in getChar.
	 */
	foreach(s; suffix) {
		putChar(s);
	}
	
	return i;
}

unittest {
	void test(const(ubyte)[] data, string expected) {
		char[128] buffer;
		auto l = expected.length;
		auto sbuf = buffer[0 .. l];
		
		assert(encode!getZBase32(data, buffer) == l);
		assert(sbuf == expected, sbuf ~ " vs " ~ expected);
	}
	
	test([], "");
	
	test([0x00], "yy");
	test([0x01], "yr");
	test([0x81], "or");
	test([0xff], "9h");
	
	test([0x00, 0x00], "yyyy");
	test([0xf5, 0x99], "6sco");
	test([0xff, 0xff], "999o");
	
	test([0x00, 0x00, 0x00], "yyyyy");
	test([0xab, 0xcd, 0xef], "ixg66");
	test([0xff, 0xff, 0xff], "99996");
	
	test([0x00, 0x00, 0x00, 0x00], "yyyyyyy");
	test([0x89, 0xab, 0xcd, 0xef], "tgih55a");
	test([0xff, 0xff, 0xff, 0xff], "999999a");
	
	test([0x00, 0x00, 0x00, 0x00, 0x00], "yyyyyyyy");
	test([0x67, 0x89, 0xab, 0xcd, 0xef], "c6r4zuxx");
	test([0xff, 0xff, 0xff, 0xff, 0xff], "99999999");
	
	test([0x00, 0x00, 0x00, 0x00, 0x00, 0x00], "yyyyyyyyyy");
	test([0x45, 0x67, 0x89, 0xab, 0xcd, 0xef], "eiuauk6p7h");
	test([0xff, 0xff, 0xff, 0xff, 0xff, 0xff], "999999999h");
}

/**
 * Support for RFC4648 base32
 *
 * https://tools.ietf.org/html/rfc4648#section-6
 */
char getBase32(uint n) in {
	assert(n == (n & 0x1f));
} body {
	// As '2' == 26, this should simplify :)
	auto r = (n < 26)
		? 'A' + n
		: '2' + n - 26;
	
	return cast(char) r;
}

unittest {
	void test(uint n, char c) {
		assert(getBase32(n) == c);
	}
	
	test(0, 'A');
	test(1, 'B');
	test(9, 'J');
	test(12, 'M');
	test(25, 'Z');
	test(26, '2');
	test(27, '3');
	test(31, '7');
}

/**
 * Support for RFC4648 base32hex
 *
 * https://tools.ietf.org/html/rfc4648#section-7
 */
char getBase32Hex(uint n) in {
	assert(n == (n & 0x1f));
} body {
	auto r = (n < 10)
		? '0' + n
		: 'A' + n - 10;
	
	return cast(char) r;
}

unittest {
	void test(uint n, char c) {
		assert(getBase32Hex(n) == c);
	}
	
	test(0, '0');
	test(1, '1');
	test(4, '4');
	test(9, '9');
	test(10, 'A');
	test(15, 'F');
	test(27, 'R');
	test(31, 'V');
}

/**
 * Support for zbase32
 *
 * http://philzimmermann.com/docs/human-oriented-base-32-encoding.txt
 */
char getZBase32(uint n) in {
	assert(n == (n & 0x1f));
} body {
	return "ybndrfg8ejkmcpqxot1uwisza345h769".ptr[n];
}

unittest {
	void test(uint n, char c) {
		assert(getZBase32(n) == c);
	}
	
	test(0, 'y');
	test(1, 'b');
	test(4, 'r');
	test(9, 'j');
	test(10, 'k');
	test(15, 'x');
	test(27, '5');
	test(31, '9');
}

/**
 * Support for bech32
 *
 * https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki#Bech32
 */
char getBech32(uint n) in {
	assert(n == (n & 0x1f));
} body {
	return "qpzry9x8gf2tvdw0s3jn54khce6mua7l".ptr[n];
}

unittest {
	void test(uint n, char c) {
		assert(getBech32(n) == c);
	}
	
	test(0, 'q');
	test(1, 'p');
	test(4, 'y');
	test(9, 'f');
	test(10, '2');
	test(15, '0');
	test(27, 'm');
	test(31, 'l');
}

/*********************
 * Decoding routines.
 ********************/

/**
 * Find out the size of the data given the size
 * of the string to decode.
 */
size_t getSizeFromBase32(size_t length) {
	if (length == 0) {
		return 0;
	}
	
	return ((length * 5  - 1) / 8) + 1;
}

size_t decode(
	alias decodeChar,
	bool discardPartial = true,
)(const(char)[] str, ubyte[] data) in {
	// assert(data.length >= getSizeFromBase32(str.length));
} body {
	size_t i;
	
	uint getByte() out(r) {
		assert(r == (r & 0x1f));
	} body {
		return decodeChar(str[i++]);
	}
	
	// Useful ?
	/+
	while ((str.length - i) >= 8 && data.ptr >= 8) {
		scope(success) data = data[5 .. $];
		
		auto b0 = getByte();
		auto b1 = getByte();
		auto b2 = getByte();
		auto b3 = getByte();
		auto b4 = getByte();
		auto b5 = getByte();
		auto b6 = getByte();
		auto b7 = getByte();
		
		auto n = ((cast(ulong) b0) << 35) | ((cast(ulong) b1) << 30):
		n |= (b2 << 25) | (b3 << 20) | (b4 << 15);
		n |= (b5 << 10) | (b6 << 5) | b7;
		
		import core.bitop;
		*(cast(ulong*) data.ptr) = bswap(n << 24);
	}
	// +/
	
	// May we are running out of str and we can't patch ulong.
	while ((str.length - i) >= 8) {
		scope(success) data = data[5 .. $];
		
		auto c0 = getByte();
		auto c1 = getByte();
		auto c2 = getByte();
		auto c3 = getByte();
		auto c4 = getByte();
		auto c5 = getByte();
		auto c6 = getByte();
		auto c7 = getByte();
		
		auto h = (c0 << 3) | (c1 >> 2);
		data[0] = h & 0xff;
		
		auto n = (c1 << 30) | (c2 << 25) | (c3 << 20);
		n |= (c4 << 15) | (c5 << 10) | (c6 << 5) | c7;
		
		import core.bitop;
		*(cast(uint*) (data.ptr + 1)) = bswap(n);
	}
	
	// If we are done, bail out !
	if (str.length == i) {
		return i;
	}
	
	ubyte[5] suffixBuffer;
	ubyte[] suffix;
	
	auto suffixSize = str.length - i;
	switch (suffixSize) {
		case 1:
			suffix = suffixBuffer[0 .. 1];
			suffix[0] = (getByte() << 3) & 0x1f;
			break;
		
		case 2:
			suffix = suffixBuffer[0 .. 2];
			
			auto c0 = getByte();
			auto c1 = getByte();
			auto n = (c0 << 27) | (c1 << 22);
			
			import core.bitop;
			*(cast(ushort*) suffix.ptr) = bswap(n) & 0xffff;
			break;
		
		case 3:
			suffix = suffixBuffer[0 .. 2];
			
			auto c0 = getByte();
			auto c1 = getByte();
			auto c2 = getByte();
			auto n = (c0 << 27) | (c1 << 22) | (c2 << 17);
			
			import core.bitop;
			*(cast(ushort*) suffix.ptr) = bswap(n) & 0xffff;
			break;
		
		case 4:
			suffix = suffixBuffer[0 .. 3];
			
			auto c0 = getByte();
			auto c1 = getByte();
			auto c2 = getByte();
			auto c3 = getByte();
			
			auto h = (c0 << 3) | (c1 >> 2);
			suffix[0] = h & 0xff;
			
			auto n = (c1 << 30) | (c2 << 25) | (c3 << 20);
			
			import core.bitop;
			*(cast(ushort*) (suffix.ptr + 1)) = bswap(n) & 0xffff;
			break;
		
		case 5:
			suffix = suffixBuffer[0 .. 4];
			
			auto c0 = getByte();
			auto c1 = getByte();
			auto c2 = getByte();
			auto c3 = getByte();
			auto c4 = getByte();
			
			auto n = (c0 << 27) | (c1 << 22);
			n |= (c2 << 17) | (c3 << 12) | (c4 << 7);
			
			import core.bitop;
			*(cast(uint*) suffix.ptr) = bswap(n);
			break;
		
		case 6:
			suffix = suffixBuffer[0 .. 4];
			
			auto c0 = getByte();
			auto c1 = getByte();
			auto c2 = getByte();
			auto c3 = getByte();
			auto c4 = getByte();
			auto c5 = getByte();
			
			auto n = (c0 << 27) | (c1 << 22) | (c2 << 17);
			n |= (c3 << 12) | (c4 << 7) | (c4 << 2);
			
			import core.bitop;
			*(cast(uint*) suffix.ptr) = bswap(n);
			break;
		
		case 7:
			suffix = suffixBuffer[0 .. 5];
			
			auto c0 = getByte();
			auto c1 = getByte();
			auto c2 = getByte();
			auto c3 = getByte();
			auto c4 = getByte();
			auto c5 = getByte();
			auto c6 = getByte();
			
			auto h = (c0 << 3) | (c1 >> 2);
			suffix[0] = h & 0xff;
			
			auto n = (c1 << 30) | (c2 << 25) | (c3 << 20);
			n |= (c4 << 15) | (c5 << 10) | (c6 << 5);
			
			import core.bitop;
			*(cast(uint*) (suffix.ptr + 1)) = bswap(n);
			break;
		
		default:
			assert(0);
	}
	
	static if (discardPartial) {
		suffix = suffix[0 .. $ - 1];
	}
	
	import core.stdc.string;
	memcpy(data.ptr, suffix.ptr, suffix.length);
	
	return i;
}

unittest {
	void test(const(ubyte)[] expected, string str) {
		ubyte[128] buffer;
		auto l = expected.length;
		auto sbuf = buffer[0 .. l];
		
		assert(decode!getFromZBase32(str, sbuf) == str.length);
		
		import std.conv;
		assert(sbuf == expected, sbuf.to!string() ~ " vs " ~ expected.to!string());
	}
	
	test([], "");
	
	test([0x00], "yy");
	test([0x01], "yr");
	test([0x81], "or");
	test([0xff], "9h");
	
	test([0x00, 0x00], "yyyy");
	test([0xf5, 0x99], "6sco");
	test([0xff, 0xff], "999o");
	
	test([0x00, 0x00, 0x00], "yyyyy");
	test([0xab, 0xcd, 0xef], "ixg66");
	test([0xff, 0xff, 0xff], "99996");
	
	test([0x00, 0x00, 0x00, 0x00], "yyyyyyy");
	test([0x89, 0xab, 0xcd, 0xef], "tgih55a");
	test([0xff, 0xff, 0xff, 0xff], "999999a");
	
	test([0x00, 0x00, 0x00, 0x00, 0x00], "yyyyyyyy");
	test([0x67, 0x89, 0xab, 0xcd, 0xef], "c6r4zuxx");
	test([0xff, 0xff, 0xff, 0xff, 0xff], "99999999");
	
	test([0x00, 0x00, 0x00, 0x00, 0x00, 0x00], "yyyyyyyyyy");
	test([0x45, 0x67, 0x89, 0xab, 0xcd, 0xef], "eiuauk6p7h");
	test([0xff, 0xff, 0xff, 0xff, 0xff, 0xff], "999999999h");
}

/**
 * Support for RFC4648 base32
 *
 * https://tools.ietf.org/html/rfc4648#section-6
 */
uint getFromBase32(char n) out(r) {
	assert(r == (r & 0x1f));
} body {
	// We do not really care about the case here.
	uint l = (n | 0x20) - 'a';
	if (l < 26) {
		return l;
	}
	
	// As '2' == 26, this should simplify :)
	uint d = n - '2';
	if (d < 8) {
		return d + 26;
	}
	
	throw new Exception("Invalid input " ~ n);
}

unittest {
	void test(uint n, char c) {
		assert(getFromBase32(c) == n);
	}
	
	test(0, 'A');
	test(1, 'B');
	test(9, 'J');
	test(12, 'M');
	test(25, 'Z');
	test(0, 'a');
	test(1, 'b');
	test(9, 'j');
	test(12, 'm');
	test(25, 'z');
	test(26, '2');
	test(27, '3');
	test(31, '7');
}

/**
 * Support for RFC4648 base32hex
 *
 * https://tools.ietf.org/html/rfc4648#section-7
 */
uint getFromBase32Hex(char c) out(r) {
	assert(r == (r & 0x1f));
} body {
	uint n = c - '0';
	if (n < 10) {
		return n;
	}
	
	// We do not really care about the case here.
	uint l = (c | 0x20) - 'a';
	if (l < 22) {
		return l + 10;
	}
	
	throw new Exception("Invalid input " ~ c);
}

unittest {
	void test(uint n, char c) {
		assert(getFromBase32Hex(c) == n);
	}
	
	test(0, '0');
	test(1, '1');
	test(4, '4');
	test(9, '9');
	test(10, 'A');
	test(15, 'F');
	test(27, 'R');
	test(31, 'V');
	test(10, 'a');
	test(15, 'f');
	test(27, 'r');
	test(31, 'v');
}

/**
 * Support for zbase32
 *
 * http://philzimmermann.com/docs/human-oriented-base-32-encoding.txt
 */
uint getFromZBase32(char c) out(r) {
	assert(r == (r & 0x1f));
} body {
	enum Table = buildCaseInsensitiveTruthTable!getZBase32();
	auto n = Table[c];
	if (n != (n & 0x1f)) {
		throw new Exception("Invalid input " ~ c);
	}
	
	return n;
}

unittest {
	void test(uint n, char c) {
		assert(getFromZBase32(c) == n);
	}
	
	test(0, 'y');
	test(1, 'b');
	test(4, 'r');
	test(9, 'j');
	test(10, 'k');
	test(15, 'x');
	test(27, '5');
	test(31, '9');
	test(0, 'Y');
	test(1, 'B');
	test(4, 'R');
	test(9, 'J');
	test(10, 'K');
	test(15, 'X');
}

/**
 * Support for bech32
 *
 * https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki#Bech32
 */
uint getFromBech32(char c) out(r) {
	assert(r == (r & 0x1f));
} body {
	enum Table = buildCaseInsensitiveTruthTable!getBech32();
	auto n = Table[c];
	if (n != (n & 0x1f)) {
		throw new Exception("Invalid input " ~ c);
	}
	
	return n;
}

unittest {
	void test(uint n, char c) {
		assert(getFromBech32(c) == n);
	}
	
	test(0, 'q');
	test(1, 'p');
	test(4, 'y');
	test(9, 'f');
	test(10, '2');
	test(15, '0');
	test(27, 'm');
	test(31, 'l');
	test(0, 'Q');
	test(1, 'P');
	test(4, 'Y');
	test(9, 'F');
	test(27, 'M');
	test(31, 'L');
}

private auto buildTruthTable(alias getChar)() {
	ubyte[256] table;
	
	foreach (i; 0 .. 256) {
		table[i] = 0xff;
	}
	
	foreach (ubyte i; 0 .. 32) {
		table[getChar(i)] = i;
	}
	
	return table;
}

private auto buildCaseInsensitiveTruthTable(alias getChar)() {
	ubyte[256] table = buildTruthTable!getChar();
	
	foreach (C; 'A' .. 'Z') {
		auto c = C | 0x20;
		
		if (table[c] != 0xff && table[C] == 0xff) {
			table[C] = table[c];
		} else if (table[c] == 0xff && table[C] != 0xff) {
			table[c] = table[C];
		}
	}
	
	return table;
}
