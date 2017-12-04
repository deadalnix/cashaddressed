#!/usr/bin/env rdmd
module fixup;

string rebuildAddr(const ubyte[] data) {
	string ret;
	ret.reserve(data.length);
	
	size_t i = 0;
	while (data[i]) {
		enum Base = 'a' & 0xe0;
		ret ~= cast(char) (Base + data[i++]);
	}
	
	ret ~= ':';
	foreach (c; data[i + 1 .. $]) {
		import util.base32;
		ret ~= getBech32(c);
	}
	
	return ret;
}

string fixCashAddr(string addr) {
	ubyte[] data;
	size_t prefixSize;
	
	import cashaddr;
	if (!decodeData(addr, prefixSize, data)) {
		return "";
	}
	
	import util.bch;
	ulong checksum = polyMod(data);
	if (checksum == 0) {
		return rebuildAddr(data);
	}
	
	/**
	 * Ok, it gets interesting now, we have a checksum that do not match.
	 * We start by computing the syndromes and try to find a set of error
	 * that fixes the address.
	 */
	ulong[ulong] syndromes;
	foreach (p; 0 .. data.length) {
		foreach(e; 1 .. 32) {
			// Add the error;
			data[p] ^= e;
			scope(success) data[p] ^= e;
			
			ulong c = polyMod(data);
			if (c == 0) {
				return rebuildAddr(data);
			}
			
			syndromes[c ^ checksum] = p * 32 + e;
		}
	}
	
	foreach (s0, pe; syndromes) {
		if (auto s1ptr = (s0 ^ checksum) in syndromes) {
			data[pe / 32] ^= pe % 32;
			data[*s1ptr / 32] ^= *s1ptr % 32;
			return rebuildAddr(data);
		}
	}
	
	// We failed to fix.
	return "";
}

void main(string[] addrs) {
	foreach (a; addrs[1 .. $]) {
		auto fixed = fixCashAddr(a);
		if (fixed) {
			import std.stdio;
			writeln(fixed);
		}
	}
}
