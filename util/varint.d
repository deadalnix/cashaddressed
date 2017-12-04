module util.varint;

uint encode(ulong n, ubyte[] buffer) {
	if (n < 0x80) {
		if (buffer.length < 1) {
			throw new Exception("not enough space in the buffer");
		}
		
		buffer[0] = n & 0xff;
		return 1;
	}
	
	import core.bitop;
	auto bsr = bsr(n);
	
	auto offset = 0x0102040810204080 & ((2UL << bsr) - 1);
	
	// This is some black magic. We whant to divide by 7
	// but still get 8 for bsr == 63. We can aproxiamate
	// this result via a linear function and let truncate
	// do the rest.
	auto byteCount = ((bsr * 36) + 35) >> 8;
	auto e = n - offset;
	
	// If we underflow, we need to go one class down.
	if (e > n) {
		offset -= 1UL << bsr;
		byteCount--;
		e = n - offset;
	}
	
	// For some obscure reason, DMD doesn't have bswap for 16 bits integrals.
	// so we do everything with 32bits and 64bits ones.
	import core.bitop;
	
	if (byteCount == 8) {
		if (buffer.length <= 8) {
			throw new Exception("not enough space in the buffer");
		}
		
		buffer[0] = 0xff;
		*(cast(ulong*) (buffer.ptr + 1)) = bswap(e);
		return 9;
	}
	
	// This is a fast path that is usable if we have extra buffer space.
	if (buffer.length >= 8) {
		auto h = -(1 << (8 - byteCount)) & 0xff;
		auto v = bswap(e) >> ((7 - byteCount) * 8);
		*(cast(ulong*) buffer.ptr) = (h | v);
		return byteCount + 1;
	}
	
	if (buffer.length <= byteCount) {
		throw new Exception("not enough space in the buffer");
	}
	
	switch(byteCount) {
		case 1:
			*(cast(ushort*) buffer.ptr) = 0x80 | (bswap(cast(uint) e) >> 16);
			break;
		
		case 2:
			buffer[0] = (0xc0 | (e >> 16)) & 0xff;
			*(cast(ushort*) (buffer.ptr + 1)) = (bswap(cast(uint) e) >> 16) & 0xffff;
			break;
		
		case 3:
			*(cast(uint*) buffer.ptr) = 0xe0 | bswap(cast(uint) e);
			break;
		
		case 4:
			buffer[0] = (0xf0 | (e >> 32)) & 0xff;
			*(cast(uint*) (buffer.ptr + 1)) = bswap(cast(uint) e);
			break;
		
		case 5:
			*(cast(uint*) buffer.ptr) = 0xf8 | bswap(cast(uint) (e >> 16));
			*(cast(ushort*) (buffer.ptr + 4)) = bswap(cast(uint) e) >> 16;
			break;
		
		case 6:
			buffer[0] = (0xfc | (e >> 48)) & 0xff;
			*(cast(ushort*) (buffer.ptr + 1)) = bswap(cast(uint) (e >> 16)) & 0xffff;
			*(cast(uint*) (buffer.ptr + 3)) = bswap(cast(uint) e);
			break;
		
		case 7:
			*(cast(ulong*) buffer.ptr) = 0xfe | bswap(e);
			break;
		
		default:
			assert(0);
	}
	
	return byteCount + 1;
}

unittest {
	void testEncode(ulong n, ubyte[] expected) {
		ubyte[9] buffer;
		auto l = expected.length;
		auto sbuf = buffer[0 .. l];
		
		// Test fast path.
		assert(encode(n, buffer) == l);
		assert(sbuf == expected);
		
		// Test contrained path.
		assert(encode(n, sbuf) == l);
		assert(sbuf == expected);
	}
	
	testEncode(0, [0]);
	testEncode(1, [1]);
	testEncode(42, [42]);
	testEncode(127, [127]);
	
	testEncode(128, [0x80, 0x00]);
	testEncode(129, [0x80, 0x01]);
	testEncode(0x3fff, [0xbf, 0x7f]);
	testEncode(0x407f, [0xbf, 0xff]);
	
	testEncode(0x4080, [0xc0, 0x00, 0x00]);
	testEncode(0x25052, [0xc2, 0x0f, 0xd2]);
	testEncode(0x20407f, [0xdf, 0xff, 0xff]);
	
	testEncode(0x204080, [0xe0, 0x00, 0x00, 0x00]);
	testEncode(0x1234567, [0xe1, 0x03, 0x04, 0xe7]);
	testEncode(0x1020407f, [0xef, 0xff, 0xff, 0xff]);
	
	testEncode(0x10204080, [0xf0, 0x00, 0x00, 0x00, 0x00]);
	testEncode(0x312345678, [0xf3, 0x02, 0x14, 0x15, 0xf8]);
	testEncode(0x081020407f, [0xf7, 0xff, 0xff, 0xff, 0xff]);
	
	testEncode(0x0810204080, [0xf8, 0x00, 0x00, 0x00, 0x00, 0x00]);
	testEncode(0x032101234567, [0xfb, 0x18, 0xf1, 0x03, 0x04, 0xe7]);
	testEncode(0x04081020407f, [0xfb, 0xff, 0xff, 0xff, 0xff, 0xff]);
	
	testEncode(0x040810204080, [0xfc, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
	testEncode(0x0123456789abcd, [0xfd, 0x1f, 0x3d, 0x57, 0x69, 0x6b, 0x4d]);
	testEncode(0x0204081020407f, [0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
	
	testEncode(
		0x02040810204080,
		[0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	);
	testEncode(
		0xfedcba98765432,
		[0xfe, 0xfc, 0xd8, 0xb2, 0x88, 0x56, 0x13, 0xb2],
	);
	testEncode(
		0x010204081020407f,
		[0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
	);
	
	testEncode(
		0x0102040810204080,
		[0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	);
	testEncode(
		0xffffffffffffffff,
		[0xff, 0xfe, 0xfd, 0xfb, 0xf7, 0xef, 0xdf, 0xbf, 0x7f],
	);
}

ulong decode(ref const(ubyte)[] data) {
	if (data.length < 1) {
		throw new Exception("Buffer empty");
	}
	
	auto h = data[0];
	if (h < 0x80) {
		data = data[1 .. $];
		return h;
	}
	
	if (h == 0xff) {
		if (data.length <= 8) {
			throw new Exception("Ran out of buffer to read from");
		}
		
		import core.bitop;
		auto n = bswap(*(cast(ulong*) (data.ptr + 1))) + 0x0102040810204080;
		if (n < 0x0102040810204080) {
			throw new Exception("Non normalized integer");
		}
		
		data = data[9 .. $];
		return n;
	}
	
	import core.bitop;
	auto bsr = bsr(~h);
	auto byteCount = 8 - bsr;
	
	auto mask = (1UL << (byteCount * 7)) - 1;
	auto offset = 0x0102040810204080 & mask;
	
	scope(success) data = data[byteCount .. $];
	
	if (data.length >= 8) {
		import core.bitop;
		auto n = bswap(*(cast(ulong*) data.ptr)) >> (bsr * 8);
		return (n & mask) + offset;
	}
	
	if (data.length < byteCount) {
		throw new Exception("Ran out of buffer to read from");
	}
	
	switch (byteCount) {
		case 2:
			auto n = *(cast(ushort*) data.ptr);
			return (bswap(n & 0xff3f) >> 16) + offset;
		
		case 3:
			uint n = bswap(*(cast(ushort*) (data.ptr + 1)));
			ulong d = data[0] & 0x1f;
			return ((n >> 16) | (d << 16)) + offset;
		
		case 4:
			auto n = *(cast(uint*) data.ptr);
			return bswap(n & 0xffffff0f) + offset;
		
		case 5:
			uint n = bswap(*(cast(uint*) (data.ptr + 1)));
			ulong d = data[0] & 0x07;
			return (n | (d << 32)) + offset;
		
		case 6:
			uint n0 = *(cast(short*) (data.ptr + 4));
			ulong n1 = bswap(*(cast(uint*) data.ptr) & 0xffffff03);
			return (bswap(n0 << 16) | (n1 << 16)) + offset;
		
		case 7:
			uint n0 = *(cast(short*) (data.ptr + 5));
			ulong n1 = bswap(*(cast(uint*) (data.ptr + 1)));
			ulong d = data[0] & 0x01;
			return (bswap(n0 << 16) | (n1 << 16) | (d << 48)) + offset;
		
		case 8:
			auto n = *(cast(ulong*) data.ptr);
			return bswap(n & 0xffffffffffffff00) + offset;
		
		default:
			assert(0);
	}
}

unittest {
	void testDecode(ulong expected, const(ubyte)[] data) {
		ubyte[9] buffer;
		buffer[0 .. data.length] = data;
		
		const(ubyte)[] b = buffer[0 .. $];
		assert(decode(b) == expected);
		
		assert(decode(data) == expected);
		assert(data.length == 0);
	}
	
	testDecode(0, [0]);
	testDecode(1, [1]);
	testDecode(42, [42]);
	testDecode(127, [127]);
	
	testDecode(128, [0x80, 0x00]);
	testDecode(129, [0x80, 0x01]);
	testDecode(0x3fff, [0xbf, 0x7f]);
	testDecode(0x407f, [0xbf, 0xff]);
	
	testDecode(0x4080, [0xc0, 0x00, 0x00]);
	testDecode(0x25052, [0xc2, 0x0f, 0xd2]);
	testDecode(0x20407f, [0xdf, 0xff, 0xff]);
	
	testDecode(0x204080, [0xe0, 0x00, 0x00, 0x00]);
	testDecode(0x1234567, [0xe1, 0x03, 0x04, 0xe7]);
	testDecode(0x1020407f, [0xef, 0xff, 0xff, 0xff]);
	
	testDecode(0x10204080, [0xf0, 0x00, 0x00, 0x00, 0x00]);
	testDecode(0x312345678, [0xf3, 0x02, 0x14, 0x15, 0xf8]);
	testDecode(0x081020407f, [0xf7, 0xff, 0xff, 0xff, 0xff]);
	
	testDecode(0x0810204080, [0xf8, 0x00, 0x00, 0x00, 0x00, 0x00]);
	testDecode(0x032101234567, [0xfb, 0x18, 0xf1, 0x03, 0x04, 0xe7]);
	testDecode(0x04081020407f, [0xfb, 0xff, 0xff, 0xff, 0xff, 0xff]);
	
	testDecode(0x040810204080, [0xfc, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
	testDecode(0x0123456789abcd, [0xfd, 0x1f, 0x3d, 0x57, 0x69, 0x6b, 0x4d]);
	testDecode(0x0204081020407f, [0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
	
	testDecode(
		0x02040810204080,
		[0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	);
	testDecode(
		0xfedcba98765432,
		[0xfe, 0xfc, 0xd8, 0xb2, 0x88, 0x56, 0x13, 0xb2],
	);
	testDecode(
		0x010204081020407f,
		[0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
	);
	
	testDecode(
		0x0102040810204080,
		[0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	);
	testDecode(
		0xffffffffffffffff,
		[0xff, 0xfe, 0xfd, 0xfb, 0xf7, 0xef, 0xdf, 0xbf, 0x7f],
	);
}
