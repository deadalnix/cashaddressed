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
