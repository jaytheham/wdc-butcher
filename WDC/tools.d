module wdc.tools;

import std.bitmanip,
		std.stdio;

int readInt(ubyte[] source, int location)
{
	//writefln("__%x", location);
	return peek!int(source[location..location + 4]);
}

void writeInt(ubyte[] source, int location, int value)
{
	source[location] = (value & 0xff000000) >> 24;
	source[location + 1] = (value & 0xff0000) >> 16;
	source[location + 2] = (value & 0xff00) >> 8;
	source[location + 3] = value & 0xff;
}

void incrementInt(ubyte[] source, int location, int change)
{
	source.writeInt(location, source.readInt(location) + change);
}

long readLong(ubyte[] source, int location)
{
	return peek!long(source[location..location + 8]);
}

ulong readULong(ubyte[] source, int location)
{
	return peek!ulong(source[location..location + 8]);
}

float readFloat(ubyte[] source, int location)
{
	//writefln("__%x", location);
	return peek!float(source[location..location + 4]);
}

void writeFloat(ubyte[] source, int location, float value)
{
	int* data = cast(int*)&value;
	source[location] = (*data & 0xff000000) >> 24;
	source[location + 1] = (*data & 0xff0000) >> 16;
	source[location + 2] = (*data & 0xff00) >> 8;
	source[location + 3] = *data & 0xff;
}

short readShort(ubyte[] source, int location)
{
	//writefln("__%x", location);
	return peek!short(source[location..location + 2]);
}

void writeShort(ubyte[] source, int location, short value)
{
	source[location] = (value & 0xff00) >> 8;
	source[location + 1] = value & 0xff;
}

ushort readUshort(ubyte[] source, int location)
{
	return peek!ushort(source[location..location + 2]);
}

void incrementShort(ubyte[] source, int location, int change)
{
	source.writeShort(location, cast(short)(source.readShort(location) + change));
}