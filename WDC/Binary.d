module wdc.binary;

import std.conv,
	   std.zlib,
	   std.file,
	   std.format,
	   std.bitmanip,
	   std.typecons,
	   std.stdio: File, writeln, writefln;

import gfm.opengl;

import wdc.car;

class Binary
{

private:
	
	enum RegionType { PAL, NTSC };

	uint[RegionType] carAssetsOffset;
	enum carAssetsStringOffset = 0xc00;
	enum carAssetsSize = 0x80;

	RegionType region;
	ubyte[] binary;

	pure void setupArrays()
	{
		carAssetsOffset = [ RegionType.PAL : 0x83620, RegionType.NTSC : 0x81c30];
	}

public:

	this(string filePath)
	{
		setupArrays();

		File binaryHandle = File(filePath, "r");
		binary.length = cast(uint)binaryHandle.size;
		binaryHandle.rawRead(binary);
		binaryHandle.close();
		
		enforceBigEndian();

		region = binary[0x3e] == 'E' ? RegionType.NTSC : RegionType.PAL;

		writeln("Loaded ROM:");
		writeln(cast(char[])binary[0x20..0x34]);
		writefln("Version detected as %s", region);
	}

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

	Car getCar(int carIndex)
	{
		int carAssetOffset = carAssetsOffset[region] + carAssetsSize * carIndex;
		int dataBlobOffset = peek!int(binary[carAssetOffset + 0x14..carAssetOffset + 0x18]);
		int textureBlobOffset = peek!int(binary[carAssetOffset + 0x18..carAssetOffset + 0x1c]);
		
		return new Car(decompressZlibBlock(dataBlobOffset), decompressZlibBlock(textureBlobOffset));
	}

	void dumpCarData(int index)
	{
		string workingDir = getcwd();
		string outputDir = workingDir ~ "\\output";
		if (!exists(outputDir))
		{
			mkdir(outputDir);
		}
		chdir(outputDir);

		int carAssetOffset = carAssetsOffset[region] + carAssetsSize * index;
		int offset, endOffset;
		int wordNum = 5;

		while (wordNum < 0xf)
		{
			offset = (binary[carAssetOffset + wordNum * 4 + 1] << 16) +
					 (binary[carAssetOffset + wordNum * 4 + 2] << 8) +
					  binary[carAssetOffset + wordNum * 4 + 3];
			wordNum += 2;
				if (binary[offset + 0xc] == 0x78)
				{
					auto output = decompressZlibBlock(offset);
					write(format("%.2d_%.8x", index, offset), output);
					offset += output.length;
				}
				else
				{
					writefln("%x not zlib", offset);
				}
		}
		chdir(workingDir);
	}

	ubyte[] decompressZlibBlock(int offset)
	{
		int blockSize = peek!int(binary[offset..offset + 4]);
		int blockEnd = offset + blockSize;
		//int blockOutputSize = peek!int(binary[offset + 4..offset + 8]);
		int zlibSize = 0;
		ubyte[] output;
		writefln("Inflating data from %x", offset);
		offset += 0x8;

		do
		{
			offset += zlibSize;
			zlibSize = peek!int(binary[offset..offset + 4]);
			offset += 4;
			
			output ~= cast(ubyte[])uncompress(binary[offset..offset + zlibSize]);

			writefln("%x decompressed", offset);

			if (zlibSize % 2 == 1) // Next file will be aligned to short
			{
				zlibSize++;
			}
		} while (offset + zlibSize < blockEnd);

		return output;
	}
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
				// Big Endian
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