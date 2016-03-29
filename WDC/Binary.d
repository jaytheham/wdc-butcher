module wdc.binary;

import std.conv,
	   std.zlib,
	   std.file,
	   std.math,
	   std.format,
	   std.bitmanip,
	   std.typecons,
	   std.exception: enforce;
import std.stdio: File, writeln, writefln;

import gfm.opengl;

import wdc.car,
	   wdc.track,
	   wdc.tools;

class Binary
{

private:
	
	enum RegionType { PAL, NTSC };
	enum assetsStringOffset = 0xc00;

	uint[RegionType] carAssetsOffset;
	enum carAssetsSize = 0x80;
	enum carPaletteSize = 0x20;
	enum carInsertedPalettes = 8;

	uint[RegionType] trackAssetsOffset;
	enum trackAssetsSize = 0x44;

	RegionType region;
	ubyte[] binary;

	pure void setupArrays()
	{
		carAssetsOffset = [ RegionType.PAL : 0x83620, RegionType.NTSC : 0x81c30];
		trackAssetsOffset = [ RegionType.PAL : 0x92f40, RegionType.NTSC : 0x91550];
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
			nameOffset = peek!int(binary[carAssetsOffset[region] + offset
										 ..
										 carAssetsOffset[region] + offset + 4])
						 + assetsStringOffset;
			nameOffset &= 0xfffffff;
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
		int textureBlobOffset = peek!int(binary[carAssetOffset + 0x1c..carAssetOffset + 0x20]);
		int palettesOffset = peek!int(binary[carAssetOffset + 0x24..carAssetOffset + 0x28]);
		
		return new Car(decompressZlibBlock(dataBlobOffset),
						decompressZlibBlock(textureBlobOffset),
						binary[palettesOffset..palettesOffset + (carInsertedPalettes * carPaletteSize)]);
	}

	char[][] getTrackList()
	{
		int offset = 0;
		int nameSize;
		uint nameOffset;
		char[][] trackNames;
		while(binary[trackAssetsOffset[region] + offset] == 0x80)
		{
			nameOffset = peek!int(binary[trackAssetsOffset[region] + offset
										 ..
										 trackAssetsOffset[region] + offset + 4])
						 + assetsStringOffset;
			nameOffset &= 0xfffffff;
			nameSize = 0;
			while(binary[nameOffset + nameSize] != 0)
			{
				nameSize++;
			}
			trackNames ~= cast(char[])binary[nameOffset..(nameOffset + nameSize)];
			offset += trackAssetsSize;
		}
		return trackNames;
	}

	Track getTrack(int trackIndex, int trackVariation)
	{
		// get first zlib from tracks table
		int trackAsset = trackAssetsOffset[region] + (trackAssetsSize * trackIndex);
		int zlibOffset = readInt(binary, trackAsset + 0x14);
		int firstZlibEnd = readInt(binary, zlibOffset) + zlibOffset;

		ubyte[] data = decompressZlibBlock(zlibOffset);
		// Load variation data using offsets in first zlib:
		// 0x20 Offset to null data that is turned into pointers to the inflated zlibs (is it??)
		// 0x24 Count of words at above
		int indicesDescriptorOffsets = readInt(data, 0x28);
		int indicesDescriptorOffsetsCount = readInt(data, 0x2c);
		int zlibOffsetTable = readInt(data, 0x30);

		enforce(trackVariation < indicesDescriptorOffsetsCount);

		int indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(data, indicesDescriptorLocation);
		int indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		short zlibIndex;
		for (int i = 0; i < indicesCount; i++)
		{
			zlibIndex = readShort(data, indicesLocation + (i * 2));
			zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
			data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);
		}
		
		// (track sections?)
		// 0x34 Offset to null data that is turned into pointers to the inflated zlibs (is it??)
		// 0x38 Count of words at above
		indicesDescriptorOffsets = readInt(data, 0x3c);
		indicesDescriptorOffsetsCount = readInt(data, 0x40);
		zlibOffsetTable = readInt(data, 0x44);

		enforce(trackVariation < indicesDescriptorOffsetsCount);

		indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		indicesCount = readInt(data, indicesDescriptorLocation);
		indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		for (int i = 0; i < indicesCount; i++)
		{
			if (data.length % 0x10 != 0) // These data chunks must be aligned to 0x10
			{
				data.length += 0x10 - (data.length % 0x10);
			}
			zlibIndex = readShort(data, indicesLocation + (i * 2));
			zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
			data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);
		}

		// Physics data? i.e.: collision polygons?
		fnc_33a18(data, trackVariation, firstZlibEnd);
		// Correct Output to here, but it needs to be transformed:
		// After the 2200 the call to 1659c transforms the data just inflated
		// then:
		// the loop starting at 33f40 adds more data after the zlib data
		// store 0000 after zlibed data (need to check how this pointer is calc'd)
		// store 0000
		// store ffff
		// and there are more...

		
		// Next four blocks are handled by the same function
		//// 0x68 Offset to null data that is turned into pointers to the inflated zlibs (is it??)
		//// 0x6c Count of words at above
		//indicesDescriptorOffsets = readInt(data, 0x70);
		//indicesDescriptorOffsetsCount = readInt(data, 0x74);
		//// 0x78 null? Check the ASM, looks like an offset to ? gets stored here after everything is done
		//assert(readInt(data, 0x78) == 0, "78 can be something other than 0!");
		//zlibOffsetTable = readInt(data, 0x7c);

		//enforce(trackVariation < indicesDescriptorOffsetsCount);

		//indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		//indicesCount = readInt(data, indicesDescriptorLocation);
		//indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		//for (int i = 0; i < indicesCount; i++)
		//{
		//	zlibIndex = readShort(data, indicesLocation + (i * 2));
		//	zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
		//	data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);
		//	writefln("_d_%x", data.length);
		//}
		//// 0x80 Offset to null data that is turned into pointers to the inflated zlibs (is it??)
		//// 0x84 Count of words at above
		//indicesDescriptorOffsets = readInt(data, 0x88);
		//indicesDescriptorOffsetsCount = readInt(data, 0x8c);
		//// 0x90 null? Check the ASM, looks like an offset to ? gets stored here after everything is done
		//assert(readInt(data, 0x90) == 0, "90 can be something other than 0!");
		//zlibOffsetTable = readInt(data, 0x94);

		//enforce(trackVariation < indicesDescriptorOffsetsCount);

		//indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		//indicesCount = readInt(data, indicesDescriptorLocation);
		//indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		//for (int i = 0; i < indicesCount; i++)
		//{
		//	zlibIndex = readShort(data, indicesLocation + (i * 2));
		//	zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
		//	data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);
		//	writefln("_c_%x", data.length);
		//}
		//// 0x98 Offset to null data that is turned into pointers to the inflated zlibs (is it??)
		//// 0x9c Count of words at above
		//indicesDescriptorOffsets = readInt(data, 0xa0);
		//indicesDescriptorOffsetsCount = readInt(data, 0xa4);
		//// 0xa8 null? Check the ASM, looks like an offset to ? gets stored here after everything is done
		//assert(readInt(data, 0xa8) == 0, "a8 can be something other than 0!");
		//zlibOffsetTable = readInt(data, 0xac);

		//enforce(trackVariation < indicesDescriptorOffsetsCount);

		//indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		//indicesCount = readInt(data, indicesDescriptorLocation);
		//indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		//for (int i = 0; i < indicesCount; i++)
		//{
		//	zlibIndex = readShort(data, indicesLocation + (i * 2));
		//	zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
		//	data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);
		//	writefln("_b_%x", data.length);
		//}
		//// 0xb0 Offset to null data that is turned into pointers to the inflated zlibs (is it??)
		//// 0xb4 Count of words at above
		//indicesDescriptorOffsets = readInt(data, 0xb8);
		//indicesDescriptorOffsetsCount = readInt(data, 0xbc);
		//// 0xc0 null? Check the ASM, looks like an offset to ? gets stored here after everything is done
		//assert(readInt(data, 0xc0) == 0, "c0 can be something other than 0!");
		//zlibOffsetTable = readInt(data, 0xc4);

		//enforce(trackVariation < indicesDescriptorOffsetsCount);

		//indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		//indicesCount = readInt(data, indicesDescriptorLocation);
		//indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		//for (int i = 0; i < indicesCount; i++)
		//{
		//	zlibIndex = readShort(data, indicesLocation + (i * 2));
		//	zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
		//	data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);
		//	writefln("_a_%x", data.length);
		//}
		// 0xc8
		// 0xdc Doesn't use destination address
		// 0xe8

		write("myTrackData", data);

		return new Track(data);
	}

	void fnc_33a18(ref ubyte[] data, int trackVariation, int firstZlibEnd)
	{
		void fnc_1659c(ref ubyte[] data, int offset)
		{
			int cur_zlib_offset = offset; // s0
			if (data.readInt(offset) != 0) {
				data.writeInt(offset, data.readInt(offset) + cur_zlib_offset);
			}
			offset += 4;
			if (data.readInt(offset) != 0) {
				data.writeInt(offset, data.readInt(offset) + cur_zlib_offset);
			}
			offset = cur_zlib_offset + 0x24;
			if (data.readInt(offset) != 0) {
				data.writeInt(offset, data.readInt(offset) + cur_zlib_offset);
			}
			int t6 = data.readInt(cur_zlib_offset + 0x1c);
			if (t6 != 0)
			{
				data.writeInt(cur_zlib_offset + 0x20, data.readInt(cur_zlib_offset + 0x20) + cur_zlib_offset);
			}
			// fnc_164d4:
			int count = data.readInt(cur_zlib_offset + 8);
			float f20 = 0;
			int position = cur_zlib_offset; //s0
			int s2 = cur_zlib_offset + 0x28;
			int s3 = cur_zlib_offset + 0x40;
			for (int i = 0; i < count; i++)
			{
				float f4 = data.readFloat(s2);
				float f6 = data.readFloat(s2 + 4);
				float f8 = data.readFloat(s2 + 8);
				float f10 = data.readFloat(s3);
				float f16 = data.readFloat(s3 + 0x4);
				float f18 = data.readFloat(s3 + 0x8);
				f4 = f10 - f4;
				f6 = f16 - f6;
				float f0 = f4 * f4;
				f8 = f18 - f8;
				f6 = f6 * f6;
				f0 = f0 + f6;
				f8 = f8 * f8;
				f0 = f0 + f8;
				f0 = sqrt(f0);
				data.writeFloat(position + 0x34, f0);
				data.writeFloat(position + 0x38, f20);
				position += 0x18;
				s2 += 0x18;
				s3 += 0x18;
				f20 += f0;
			}
			int t6_2 = count * 0x18;
			data.writeInt(cur_zlib_offset + t6_2 + 0x34, 0);
			data.writeFloat(cur_zlib_offset + t6_2 + 0x38, f20);
			data.writeFloat(cur_zlib_offset + 0xc, f20);
		}
		int info_offset = 0x4c; // a0 sp(c8)
		int cur_zlib_offset = data.length; // a1 sp(cc)

		int total = readInt(data, info_offset + 4);

		for (int i = 0; i < total; i++)
		{
			writeInt(data, readInt(data, info_offset) + (i * 4), 0);
		}

		int previousZlibOffset = 0; // s4
		total = readInt(data, readInt(data, (readInt(data, info_offset + 8) + (trackVariation * 4))));

		// 0x4c Offset to null data that is turned into pointers to the inflated zlibs
		// 0x50 Count of words at above
		int indicesDescriptorOffsets = readInt(data, 0x54);			// sp(c8) + 8
		int indicesDescriptorOffsetsCount = readInt(data, 0x58);	// sp(c8) + c
		// 0x5c
		// 0x60
		int zlibOffsetTable = readInt(data, 0x64);					// sp(c8) + 18

		int indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(data, indicesDescriptorLocation);
		int indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		for (int i = 0; i < total; i++)
		{
			short zlibIndex = readShort(data, indicesLocation + (i * 2));
			int zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
			data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);

			data.writeInt(data.readInt(info_offset) + (zlibIndex * 4), cur_zlib_offset); // ??
			fnc_1659c(data, cur_zlib_offset);
			cur_zlib_offset = data.length;
			if (previousZlibOffset != 0)
			{
				data.writeInt(previousZlibOffset, data.readInt(data.readInt(info_offset) + (zlibIndex * 4)));
				data.writeInt(data.readInt(data.readInt(info_offset) + (zlibIndex * 4)) + 4, previousZlibOffset);
			}
			previousZlibOffset = data.readInt(data.readInt(info_offset) + (zlibIndex * 4));
			//int s2 = data.readInt(data.readInt(data.readInt(info_offset) + (zlibIndex * 4)) + 0x1c);
			//s2 *= 2;
			//int s3 = data.readInt(data.readInt(info_offset + 0x18) + (zlibIndex * 12) + 4) + (trackVariation * s2);
			// Appears to be correct output to here, apart from stuff that is changed later
		}
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

	void dumpTrackData(int index)
	{
		string workingDir = getcwd();
		string outputDir = workingDir ~ "\\output";
		if (!exists(outputDir))
		{
			mkdir(outputDir);
		}
		chdir(outputDir);

		int trackAssetOffset = trackAssetsOffset[region] + trackAssetsSize * index;
		int offset;

		offset = peek!int(binary[trackAssetOffset + 0x14..trackAssetOffset + 0x14 + 4]);

		auto output = decompressZlibBlock(offset);
		write(format("Track_%.2d_%.8x", index, offset), output);

		chdir(workingDir);
	}

	ubyte[] decompressZlibBlock(int offset)
	{
		assert(offset % 2 == 0, "Zlibs are aligned to the nearest halfword, this offset is not");
		int blockSize = peek!int(binary[offset..offset + 4]);
		int blockEnd = offset + blockSize;
		//int blockOutputSize = peek!int(binary[offset + 4..offset + 8]);
		int zlibSize = 0;
		ubyte[] output;
		writefln("Inflating zlib block from %x", offset);
		offset += 0x8;

		do
		{
			offset += zlibSize;
			zlibSize = peek!int(binary[offset..offset + 4]);
			offset += 4;
			output ~= cast(ubyte[])uncompress(binary[offset..offset + zlibSize]);

			writefln("%x inflated", offset);

			if (zlibSize % 2 == 1) // Next file will be aligned to short
			{
				zlibSize++;
			}
		} while (offset + zlibSize < blockEnd);

		return output;
	}
	
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
				writeln("Warning: ROM byte order is unrecognized, assuming Big Endian");
				break;
		}
	}
}