module cashaddr;

string encodeCashAddr(string prefix, ubyte ver, ref const ubyte[20] hash) {
	assert((ver & 0x87) == 0, "Invalid version");
	
	// Prepare the data to encode.
	ubyte[21] data;
	data[0] = ver;
	data[1 .. 21] = hash;
	
	import std.array, util.base32;
	ubyte[] encoded = uninitializedArray!(ubyte[])(prefix.length + 43);
	
	// Encode the prefix.
	foreach (i, c; prefix) {
		encoded[i] = c & 0x1f;
	}
	
	// One zero for the separator
	encoded[prefix.length] = 0;
	
	// Encode the payload
	encode(data[], encoded[prefix.length + 1 .. $ - 8]);
	
	// Prefill the checksum with zeros.
	encoded[$ - 8 .. $] = 0;
	
	// Compute the checksum.
	import util.bch;
	ulong checksum = polyMod(encoded);
	
	foreach (i; 0 .. 8) {
		encoded[$ - 1 - i] = (checksum & 0x1f);
		checksum >>= 5;
	}
	
	string ret = prefix ~ ':';
	foreach (c; encoded[prefix.length + 1 .. $]) {
		ret ~= getBech32(c);
	}
	
	return ret;
}

unittest {
	ubyte[20] hash = [
		118, 160, 64,  83, 189, 160, 168, 139, 218, 81,
		119, 184, 106, 21, 195, 178, 159, 85,  152, 115,
	];
	
	assert(encodeCashAddr("bitcoincash", 0, hash) == "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a");
	assert(encodeCashAddr("bitcoincash", 8, hash) == "bitcoincash:ppm2qsznhks23z7629mms6s4cwef74vcwvn0h829pq");
}

bool decodeData(string addr, ref size_t prefixSize, ref ubyte[] data) {
	bool lower, upper;
	foreach (i, c; addr) {
		if (c >= 'a' && c <= 'z') {
			lower = true;
			continue;
		}
		
		if (c >= 'A' && c <= 'Z') {
			upper = true;
			continue;
		}
		
		if (c >= '0' && c <= '9') {
			// No numbers in the prefix.
			if (prefixSize == 0) {
				return false;
			}
			
			continue;
		}
		
		if (c == ':') {
			// No empty prefix or several prefixes.
			if (i == 0 || prefixSize != 0) {
				return false;
			}
			
			prefixSize = i;
			continue;
		}
		
		// Invalid character.
		return false;
	}
	
	// No mixed case. Check for prefix.
	if ((prefixSize == 0) || (lower && upper)) {
		return false;
	}
	
	if (addr.length != prefixSize + 43) {
		return false;
	}
	
	string prefix = addr[0 .. prefixSize];
	
	import std.array;
	data = uninitializedArray!(ubyte[])(prefixSize + 43);
	
	// Fill in the prefix.
	foreach (i, c; prefix) {
		data[i] = c & 0x1f;
	}
	
	// Separator is 0.
	data[prefixSize] = 0;
	
	// Now the payload.
	foreach (i, c; addr[prefixSize + 1 .. $]) {
		import util.base32;
		data[prefixSize + 1 + i] = getFromBech32(c) & 0x1f;
	}
	
	return true;
}

bool decodeCashAddr(string addr, ref string prefix, ref ubyte ver, ref ubyte[20] hash) {
	ubyte[] data;
	size_t prefixSize;
	if (!decodeData(addr, prefixSize, data)) {
		return false;
	}
	
	// Verify the checksum.
	import util.bch;
	if (polyMod(data) != 0) {
		return false;
	}
	
	import util.base32;
	ubyte[21] decoded;
	decode(data[prefixSize + 1 .. $ - 8], decoded[]);
	
	ver = decoded[0];
	if ((ver & 0x87) != 0) {
		return false;
	}
	
	prefix = addr[0 .. prefixSize];
	hash = decoded[1 .. 21];
	return true;
}

unittest {
	ubyte[20] expectedHash = [
		118, 160, 64,  83, 189, 160, 168, 139, 218, 81,
		119, 184, 106, 21, 195, 178, 159, 85,  152, 115,
	];

	string prefix;
	ubyte ver;
	ubyte[20] hash;
	
	assert(decodeCashAddr("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a", prefix, ver, hash));
	assert(prefix == "bitcoincash");
	assert(ver == 0);
	assert(hash == expectedHash);
	
	assert(decodeCashAddr("bitcoincash:ppm2qsznhks23z7629mms6s4cwef74vcwvn0h829pq", prefix, ver, hash));
	assert(prefix == "bitcoincash");
	assert(ver == 8);
	assert(hash == expectedHash);
}
