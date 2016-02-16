module wdc.binary;

import std.stdio;

class Binary
{
	private
	{
		enum RegionType { PAL, NTSC };
		RegionType region;
		ubyte[] binary;

		uint[RegionType] carAssetsOffset;
		enum carAssetsStringOffset = 0xc00;
		enum carAssetsSize = 0x80;
	}

	private void setupArrays()
	{
		carAssetsOffset = [ RegionType.PAL : 0x83620, RegionType.NTSC : 0x81c30];
	}

	this(string filePath)
	{
		setupArrays();

		File binaryHandle = File(filePath, "r");
		binary.length = cast(uint)binaryHandle.size;
		binaryHandle.rawRead(binary);
		binaryHandle.close();
		
		enforceBigEndian();

		region = binary[0x3e] == 0x45 ? RegionType.NTSC : RegionType.PAL;

		writeln("Loaded ROM:");
		writeln(cast(char[])binary[0x20..0x34]);
		writefln("Version detected as %s", region);
	}

public:
	char[][] getCarList()
	{
		int offset = 0;
		int nameSize;
		uint nameOffset;
		char[][] carNames;
		while(binary[carAssetsOffset[region] + offset] == 0x80)
		{
			nameOffset = (binary[carAssetsOffset[region] + offset + 1] << 16) +
						 (binary[carAssetsOffset[region] + offset + 2] << 8) +
						 binary[carAssetsOffset[region] + offset + 3] +
						 carAssetsStringOffset;
			nameSize = 0;
			while(binary[nameOffset + nameSize] != 0)
			{
				nameSize++;
			}
			carNames ~= cast(char[])binary[nameOffset..(nameOffset + nameSize)];
			offset += carAssetsSize;
		}
		return carNames;
	}
	// getCar
	// getTrackList
	// getTrack
	// replaceCar
	// replaceTrack
	// deleteCar?
	// addcar?

private:
	void enforceBigEndian()
	{
		//BE 8037 1240
		//BS 3780 4012
		//LE 4012 3780
		switch(binary[0])
		{
			case 0x80:
				// Big Endion
				break;
			case 0x40:
				// Little Endian
				ubyte heldByte;
				foreach(i, curByte; binary)
				{
					if (i % 4 == 3)
					{
						heldByte = binary[i - 3];
						binary[i - 3] = curByte;
						binary[i] = heldByte;

						heldByte = binary[i - 2];
						binary[i - 2] = binary[i - 1];
						binary[i - 1] = heldByte;
					}
				}
				break;
			case 0x37:
				// Byte Swapped
				ubyte evenByte;
				foreach(i, curByte; binary)
				{
					if (i % 2 == 0)
					{
						evenByte = curByte;
					}
					else
					{
						binary[i - 1] = curByte;
						binary[i] = evenByte;
					}
				}
				break;
			default:
				writeln("ROM byte order is unrecognized, assuming Big Endian");
				break;
		}
	}
}