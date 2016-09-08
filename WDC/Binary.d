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
	ubyte[] curTrackData;

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

		curTrackData = decompressZlibBlock(zlibOffset);
		// TODO: Is there any processing done to the initial zlib?
		// TODO: I think so! there are differences at 0x30c

		// From here is fnc_34c84:
		// Load variation data using offsets in first zlib:
		fnc_334f8(trackVariation, firstZlibEnd);
		
		// Track sections?
		//fnc_3373c(data, trackVariation, firstZlibEnd);

		// Physics data? i.e.: collision polygons?
		//fnc_33a18(data, trackVariation, firstZlibEnd);
		// Correct Output to here, but it needs to be transformed

		
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

	// Does RAM reads
	void fnc_2ac60(int a0, int a1, int a2, int a3, int sp10)
	{
		int sp20 = a0;
		// This reads from RAM!
		int v0 = 0;//(ram.readInt(0x7fd30) * 20) + (sp20 * 4) + 0xb73d0;
		int v1 = curTrackData.readInt(v0);
		if (v1 < 0x7e)
		{
			curTrackData.incrementInt(v0, 1);
		}

		int a0_2 = ((curTrackData.readInt(0x7fd30) * 5) * 1024) + (sp20 * 1024) + (v1 * 8) + 0xb4bd0;
		v0 = (((a1 * 256) & 0xf800) | ((a2 * 8) & 0x7c0)) | ((a3 / 4) & 0x3e);
		int t8 = v0 | 1;
		int t1 = (t8 | (t8 * 65536));
		curTrackData.writeInt(a0_2 + 8, t1);

		//v0 = fnc_71930(); v0 = Count (mfc0)

		curTrackData.writeInt(a0_2 + 4, v0 - curTrackData.readInt(0x7fd3c));
	}

	// Does CACHE ops ... don't know how to handle them
	void fnc_6fcb0(int a0, int a1)
	{
		if (a1 > 0)
		{
			if (a1 < 0x2000)
			{
				int t1 = a0 + a1;
				if (a0 < t1)
				{
					t1 -= 0x10;
					int t2 = a0 & 0xf;
					if (t2 != 0)
					{
						int t0 = a0 - t2;
						// TODO
					}
					else
					{
						// d00
					}
				}
				else
				{
					return;
				}
			}
		}
		else
		{
			return;
		}
		//38
	}

	void fnc_1dc0(int a0, int a1, int a2, int a3, int sp48)
	{
		if (a3 == 0)
		{
			a3 = a2 - a1;
			if (a3 == 0)
			{
				return;
			}
		}
		
		if (sp48 == 0)
		{
			// Skip as does CACHE ops, game loads without it
			//fnc_6fcb0(a0, a3);
		}
		// Skip this as it needs RAM reads, game loads without it
		//fnc_2ac60(0, 0xff, 0xff, 0, 0x8009a080); // The last arg isn't used by this func, is actually arg?
		while (a3 >= 0x1001)
		{
			fnc_6fd60(fnc_470(), 0, 0, a1, a0, 0x1000, 0x800aa580); // Last three are sp10, sp14, sp18
			a3 -= 0x1000;
			a1 += 0x1000;
			a0 += 0x1000;
		}
		fnc_6fd60(fnc_470(), 0, 0, a1, a0, a3, 0x800aa580); // Last three are sp10, sp14, sp18
	}

	void fnc_2060(int a0, int a1, int a2, int a3)
	{
		fnc_1dc0(a0, a1, a2, a3, 0);

		fnc_53c();
	}

	void fnc_334f8(int trackVariation, int firstZlibEnd)
	{
		// All writes in this function are emulated
		//sp38=a0=0x20=start of main zlib+0x20
		//sp3c=a1=end of current data
		//sp40=a2=track variation

		int inflatedDataPointers = readInt(curTrackData, 0x20);
		// 0x24 inflatedDataPointersCount Count of words at above
		int indicesDescriptorOffsets = readInt(curTrackData, 0x28);
		int indicesDescriptorOffsetsCount = readInt(curTrackData, 0x2c);
		int zlibOffsetTable = readInt(curTrackData, 0x30);

		// @33544	Set each of the inflatedDataPointers to 0x00000000

		enforce(trackVariation < indicesDescriptorOffsetsCount);

		int indicesDescriptorLocation = readInt(curTrackData, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(curTrackData, indicesDescriptorLocation);
		int indicesLocation = readInt(curTrackData, indicesDescriptorLocation + 4);

		short zlibIndex;
		int zlibOffset;
		int cur_zlib_start;
		for (int i = 0; i < indicesCount; i++)
		{
			cur_zlib_start = curTrackData.length;
			zlibIndex = readShort(curTrackData, indicesLocation + (i * 2)); // s1
			zlibOffset = readInt(curTrackData, zlibOffsetTable + (zlibIndex * 12));
			// JAL function_0x20b0(zlibOffset)
			curTrackData ~= decompressZlibBlock(firstZlibEnd + zlibOffset); // JAL function_0x2200
			// @33628: // This gets added to by function_0x2fd08 @3363c, I do it it one step there
			//curTrackData.writeInt(inflatedDataPointers + (zlibIndex * 4), curTrackData.readInt(zlibOffsetTable + (zlibIndex * 12) + 8));
			int info_offset = curTrackData.readInt(zlibOffsetTable + (zlibIndex * 12) + 8);
			writefln("** %x  %x", inflatedDataPointers + (zlibIndex * 4), cur_zlib_start + info_offset );
			// @3363c:
			curTrackData.writeInt(inflatedDataPointers + (zlibIndex * 4), cur_zlib_start + info_offset);
			// @32934:
			// cur_zlib_start + info_offset = pointer to this zlibs start
			curTrackData.writeInt(cur_zlib_start + info_offset, cur_zlib_start);
			// cur_zlib_start + info_offset + 8 = internal pointer
			curTrackData.writeInt(cur_zlib_start + info_offset + 8, curTrackData.readInt(cur_zlib_start + info_offset + 8) + cur_zlib_start);
			// cur_zlib_start + info_offset + 10 = internal pointer
			curTrackData.writeInt(cur_zlib_start + info_offset + 0x10, curTrackData.readInt(cur_zlib_start + info_offset + 0x10) + cur_zlib_start);
			// cur_zlib_start + info_offset + 18 = internal pointer
			curTrackData.writeInt(cur_zlib_start + info_offset + 0x18, curTrackData.readInt(cur_zlib_start + info_offset + 0x18) + cur_zlib_start);

			int unknown = curTrackData.readInt(inflatedDataPointers + (zlibIndex * 4));
			int unknown2 = curTrackData.readInt(unknown + 0x1c);
			int unknown3 = curTrackData.readInt(zlibOffsetTable + (zlibIndex * 12) + 0x4) + (trackVariation * (unknown2 * 0x4));
			int unknown4 = a2 = curTrackData.readInt(zlibOffsetTable + (zlibIndex * 12) + 0x4) + (trackVariation * (unknown2 * 0x4)) + (unknown2 * 0x4);
			
			// This does transformation of the data, but also relys on reads from RAM ...
			fnc_2060(curTrackData.readInt(unknown + 0x18), unknown3, unknown4, unknown2 * 0x4);
		}

		/*
		Assembly:
		{

			0x33500		(sp + 0x38) = addressMainZlib + 0x20

			0x33504		(sp + 0x3c) = addressCurrentDataEnd

			0x33508		(sp + 0x40) = trackVariation

			0x33520		s0 = 0x0

			0x33524		inflatedDataPointersCount = (LW  (addressMainZlib + 0x24))

			0x33528		at = (s0 < t7)

			0x3352c		while  (s0 < inflatedDataPointersCount)

					{

			0x33544				*(int*)(inflatedDataPointers + (s0 * 0x4)) = 0

			0x3354c				s0++	

					}

			0x33568		s0 = 0x0

			0x33574		t8 = ((LW  (addressMainZlib + 0x28)) + (trackVariation * 0x4))

			0x33578		indicesDescriptorLocation = (LW  t8)

			0x3357c		indicesCount = (LW  t9)

			0x33580		at = (s0 < t0)

			0x33584		while  (s0 < indicesCount)

					{

			0x335a0				t6 = (indicesDescriptorOffsets + (trackVariation * 0x4))

			0x335a4				indicesDescriptorLocation = (LW  t6)

			0x335ac				t9 = (indicesLocation + (s0 * 0x2))

			0x335b0				zlibIndex = s1 = (LHU  t9)

			0x335c8				t2 = (zlibOffsetTable + (zlibIndex  * 12))

			0x335d0				zlibOffset = (LW  t2)

							JAL function_0x20b0(zlibOffset)

			0x335d8				t4 = addressMainZlib + 0x20

			0x335ec				a0 = addressCurrentDataEnd = (LW  (sp + 0x3c))

			0x335f4				a1 = zlibOffset = (LW  (zlibOffsetTable) + (zlibIndex * 12)))

			0x335fc				a2 = 0x0

							JAL function_0x2200(a0, a1, a2)

			0x33624				t6 = (inflatedDataPointers + (zlibIndex * 0x4))

			0x33628				(SW  t6) = (LW  (zlibOffsetTable + (zlibIndex * 12) + 0x8))

			0x33634				a1 = addressCurrentDataEnd

			0x33640				a0 = (inflatedDataPointers + (zlibIndex * 0x4))

							JAL function_0x2fd08(a0, a1)

			0x3364c				a1 = addressCurrentDataEnd

			0x3365c				a0 = (LW  (inflatedDataPointers  + (zlibIndex * 0x4)))

							JAL function_0x32934(a0, a1)


			0x33668				sp + 0x3c += v0

			0x3367c				t0 = (LW  (inflatedDataPointers + (zlibIndex  * 0x4)))

			0x33680				s2 = (LW  (t0 + 0x1c))


			0x33690				t8 = (LW  (sp + 0x38))

			0x33694				

			0x33698				$LO = (trackVariation * (s2 * 0x4))


			0x336a8				t3 = (zlibOffsetTable + (zlibIndex * 12))


			0x336bc				t9 = (LW  (sp + 0x38))


			0x336c4				a1 = ((LW  (t3 + 0x4)) + $LO)
				

			0x336cc				a2 = (((LW  (t3 + 0x4)) + $LO) + (s2 * 0x4))

			0x336d0				a3 = (s2 * 0x4)


			0x336d8				t2 = (LW (inflatedDataPointers + (zlibIndex * 0x4)))

			0x336e0				a0 = (LW  (t2 + 0x18))

							JAL function_0x2060()
				

			0x336ec				s0++

			0x3370c			

					}


			0x33714		v0 = (LW  (sp + 0x3c))



					Return
		}
		*/
	}

	void fnc_3373c(ref ubyte[] data, int trackVariation, int firstZlibEnd)
	{
		// a0 = sp38 = primaryZlib + 0x34
		// a1 = sp3c = end of current data / start of zlib being processed

		// 0x34 Offset to null data that is turned into pointers into the inflated zlibs
		// 0x38 Count of words at above
		int indicesDescriptorOffsets = readInt(data, 0x3c);
		int indicesDescriptorOffsetsCount = readInt(data, 0x40);
		int zlibOffsetTable = readInt(data, 0x44);

		enforce(trackVariation < indicesDescriptorOffsetsCount);

		int indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(data, indicesDescriptorLocation);
		int indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		short zlibIndex;
		int zlibOffset;
		int cur_zlib_start;
		for (int i = 0; i < indicesCount; i++)
		{
			if (data.length % 0x10 != 0) // These data chunks must be aligned to 0x10
			{
				data.length += 0x10 - (data.length % 0x10);
			}
			cur_zlib_start = data.length;
			zlibIndex = readShort(data, indicesLocation + (i * 2));
			zlibOffset = readInt(data, zlibOffsetTable + (zlibIndex * 12));
			data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);

			//data.writeInt(0x34 + (zlibIndex * 4), data.readInt(zlibOffsetTable + (zlibIndex * 0x12) + 8));
			int info_offset = data.readInt(zlibOffsetTable + (zlibIndex * 12) + 8);
			data.writeInt(data.readInt(0x34) + (zlibIndex * 4), cur_zlib_start + info_offset);

			// TODO: All these and other internal pointers must be updated with the offset
			// a0 = cur_zlib_start + info_offset
			// a1 = sp3c
			// info_offset + 0x18 = internal pointer
			data.incrementInt(cur_zlib_start + info_offset + 0x18, cur_zlib_start);
			// info_offset + 0x20 = internal pointer
			data.incrementInt(cur_zlib_start + info_offset + 0x20, cur_zlib_start);

			for (int s0 = 0; s0 < data[cur_zlib_start + info_offset + 0x1e]; s0++)
			{
				// a1 = sp3c
				int a0 = data.readInt(cur_zlib_start + info_offset + 0x18) + (s0 * 16);
				if (a0 != 0)
				{
					//	a0 is an internal pointer
					data.incrementInt(a0, cur_zlib_start);
					//	az = data.readInt(a0)
					//	az + 8 = internal pointer
					data.incrementInt(a0 + 8, cur_zlib_start);
					//	az + 0x10 = internal pointer
					data.incrementInt(a0 + 0x10, cur_zlib_start);
					//	az + 0x18 = internal pointer
					data.incrementInt(a0 + 0x18, cur_zlib_start);
					//	az + 0x20 = internal pointer
					data.incrementInt(a0 + 0x20, cur_zlib_start);
				}
			} // 31f4c
			for (int s0 = 0; s0 < data[cur_zlib_start + info_offset + 0x1f]; s0++)
			{
				// a0 = info_offset + 0x20 + (s0 * 20)
				// a1 = sp3c
				data[info_offset + 0x20 + (s0 * 20)] += 0x7b;
			}
			int a_0 = data.readInt(cur_zlib_start + info_offset + 0x8);
			if (a_0 != 0)
			{
				//	a0 is an internal pointer
				data.incrementInt(a_0, cur_zlib_start);
				//	az = data.readInt(a0)
				//	az + 8 = internal pointer
				data.incrementInt(a_0 + 8, cur_zlib_start);
				//	az + 0x10 = internal pointer
				data.incrementInt(a_0 + 0x10, cur_zlib_start);
				//	az + 0x18 = internal pointer
				data.incrementInt(a_0 + 0x18, cur_zlib_start);
				//	az + 0x20 = internal pointer
				data.incrementInt(a_0 + 0x20, cur_zlib_start);
			}
		}
	}

	void fnc_33a18(ref ubyte[] data, int trackVariation, int firstZlibEnd)
	{
		void fnc_164d4(ref ubyte[] data, int zlib_offset)
		{
			int count = data.readInt(zlib_offset + 8);
			float f20 = 0;
			int position = zlib_offset; //s0
			int s2 = zlib_offset + 0x28;
			int s3 = zlib_offset + 0x40;
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
			data.writeInt(zlib_offset + t6_2 + 0x34, 0);
			data.writeFloat(zlib_offset + t6_2 + 0x38, f20);
			data.writeFloat(zlib_offset + 0xc, f20);
		}
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
			fnc_164d4(data, cur_zlib_offset);
		}
		void fnc_34a08(ref ubyte[] data, int info_offset)
		{
			int first_zlib = data.readInt(info_offset + 0x10);
			int zlib_offset = first_zlib;
			float sp1c = 0f;
			if (first_zlib != 0)
			{
				do
				{
					fnc_164d4(data, zlib_offset);
					data.writeFloat(zlib_offset + 0x10, sp1c);
					sp1c += data.readFloat(zlib_offset + 0xc);
					zlib_offset = data.readInt(zlib_offset);
				} while (zlib_offset != first_zlib);
				data.writeFloat(info_offset + 0x14, sp1c);
			}
			else
			{
				data.writeFloat(info_offset + 0x14, 1.0f);
			}
		}
		int info_offset = 0x4c; // a0 sp(c8)
		int cur_zlib_offset = data.length; // a1 sp(cc)
		// a2 = spd0 = trackvariation
		int total = readInt(data, info_offset + 4);

		for (int i = 0; i < total; i++)
		{
			writeInt(data, readInt(data, info_offset) + (i * 4), 0);
		}

		int previousZlibOffset = 0; // s4
		total = readInt(data, readInt(data, (readInt(data, info_offset + 8) + (trackVariation * 4))));

		int varDataPointers = data.readInt(info_offset); // 0x4c Offset to null data that is turned into pointers to the inflated zlibs
		// 0x50 Count of words at above
		int indicesDescriptorOffsets = readInt(data, 0x54);			// sp(c8) + 8
		int indicesDescriptorOffsetsCount = readInt(data, 0x58);	// sp(c8) + c
		// 0x5c First zlib pointer
		// 0x60
		int zlibOffsetTable = readInt(data, 0x64);					// sp(c8) + 18

		int indicesDescriptorLocation = readInt(data, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(data, indicesDescriptorLocation);
		int indicesLocation = readInt(data, indicesDescriptorLocation + 4);

		for (int i = 0; i < total; i++)
		{
			short zlibIndex = data.readShort(indicesLocation + (i * 2)); // s1?
			int zlibOffset = data.readInt(zlibOffsetTable + (zlibIndex * 12));

			data ~= decompressZlibBlock(firstZlibEnd + zlibOffset);

			data.writeInt(data.readInt(info_offset) + (zlibIndex * 4), cur_zlib_offset);

			fnc_1659c(data, cur_zlib_offset);

			if (previousZlibOffset != 0)
			{
				data.writeInt(previousZlibOffset, cur_zlib_offset);
				data.writeInt(cur_zlib_offset + 4, previousZlibOffset);
			}
			previousZlibOffset = cur_zlib_offset;
			cur_zlib_offset = data.length;
			int s2 = data.readInt(data.readInt(data.readInt(info_offset) + (zlibIndex * 4)) + 0x1c);
			s2 *= 2;
			int s3 = data.readInt(data.readInt(info_offset + 0x18) + (zlibIndex * 12) + 4) + (trackVariation * s2);
			fnc_2060(data, data.readInt(data.readInt(varDataPointers + (zlibIndex * 4)) + 0x20), s3, s3 + s2, s2);
		}
		data.writeInt(info_offset + 0x10, data.readInt(
			data.readInt(info_offset) +
			(data.readShort(indicesLocation) * 4))); // Set pointer to first variation data

		if (previousZlibOffset != 0)
		{
			int firstZlibOffset = data.readInt(info_offset + 0x10);
			data.writeInt(previousZlibOffset, firstZlibOffset);
			data.writeInt(firstZlibOffset + 4, previousZlibOffset);
		}
		// Here's where the s4 / t2 loop that does nothing (?) goes
		fnc_34a08(data, info_offset);
		
		int spa8;
		int spb0 = data.readInt(info_offset + 0x10); // first zlib pointer?
		int last_zlib_end = cur_zlib_offset; // spac
		// there's a big if here but I don't think it ever fails:
		assert(spb0 != 0, "Well I was wrong about that");
		for (int i = 0; i < 2; i++) // i is spa0
		{
			int spcc;
			int sp9c = 0;
			if (i != 0) // 33d6c
			{
				spa8 = spb0; // pretty sure spb0 is the first var zlib pointer
				do
				{
					data.writeInt(spa8 + 0x24, (sp9c * 2) + last_zlib_end);
					for (int h = 0; h < data.readInt(spa8 + 8); h++)
					{
						int sp98 = data.readUshort((spa8 + (h * 0x18)) + 0x3c);
						// these variation zlibs have a 0x3c header with X 0x18 sized data afterwards ?
						data.writeShort((spa8 + (h * 0x18)) + 0x3c, cast(short)sp9c);

						short t2 = data.readShort(last_zlib_end + (sp98 * 2));
						short t3 = data.readShort(last_zlib_end + (sp98 * 2) + 2);
						sp9c += (t2 * 2) + (t3 * 2) + 1;
					}
					spa8 = data.readInt(spa8);
				} while (spa8 != spb0); // while we haven't looped back to the first var zlib ?
				spa8 = spb0;
				do // 33e54
				{
					for (int h = 0; h < data.readInt(spa8 + 8); h++)
					{
						ushort t4 = data.readUshort((spa8 + (h * 0x18)) + 0x3c);
						data.writeShort(last_zlib_end + (t4 * 2), 0);
					} // 33ea4
					spa8 = data.readInt(spa8); // get next zlib

				} while (spa8 != spb0); // 33ec0 while not back at first zlib
				// JAL 6f63c("edge database size = %d bytes\n", sp9c * 2)
				writefln("edge database size = %d bytes", sp9c * 2);
				if (sp9c >= 0x2801)
				{
					// JAL 3c8a8("Physics edge list is too big; tell Brian Fehdrau")
					assert(0, "Physics edge list is too big; tell Brian Fehdrau");
				} // 33efc
				// this is padding the physics edge data out right?
				spcc = (((sp9c + 7) & 0xfffffff8) * 2) + last_zlib_end;
				while ((data.length % 8) != 0)
				{
					data.length += 1;
				}
			}
			else
			{ // 33f20
				spa8 = spb0;
				do
				{
					for (int h = 0; h < data.readInt(spa8 + 8); h++)
					{
						data.length += 6;
						data.writeShort(spa8 + (h * 0x18) + 0x3c, cast(short)sp9c);
						data.writeShort(last_zlib_end + (sp9c * 2), 0);
						data.writeShort(last_zlib_end + (sp9c * 2) + 2, 0);
						data.writeShort(last_zlib_end + (sp9c * 2) + 4, cast(short)0xffff);
						sp9c += 3;
					} // 33fc0
					spa8 = data.readInt(spa8);
				} while (spa8 != spb0);
			} // 33fdc
			// word at 821b0 = primary_zlib ?
			// while h < count of zlib indices in this lot of variation data
			int indices_descriptor = data.readInt(data.readInt(0x28) + (trackVariation * 4));
			int indices_count = data.readInt(indices_descriptor);
			int indices_offset = data.readInt(indices_descriptor + 4);
			write("_myTrackData", data);
			for (int index_num = 0; index_num < indices_count; index_num++)
			{
				ushort index_value = data.readUshort(indices_offset + (index_num * 2)); //sp94
				int sp90 = data.readInt(data.readInt(0x20) + (index_value * 4));// zlib info pointer
				int sp8c = data.readInt(sp90 + 8); // pointer
				int sp88 = data.readInt(sp90);		// zlib start pointer
				int sp84 = data.readInt(sp90 + 4);	// count
				for (int sp80 = 0; sp80 < sp84; sp80++)
				{
					int spa4 = 0;
					int[3] sp74;
					if (data[sp88 + 8] == 0x80) // true
					{
						short sp72 = data.readShort(sp88 + 6); // = 0
						do
						{
							// sp70 = *79894 = 0
							short sp70 = data.readShort(data.readInt(sp90 + 0x10) + (sp72 * 12) + (spa4 * 4));
							short t2 = sp70;
							int s5 = sp70 == 0xffff ? 1 : 0;// sp70 + 1; on n64 overflows ffff to 0
							if (s5 == 0) // unsigned compare
							{
								// s5 = *78358 = pointer from 0x20 var data
								//writefln("__  %x  %x", data.readInt(0x20), data.readInt(0x20) + (t2 * 4));
								s5 = data.readInt(data.readInt(0x20) + (t2 * 4));
								s5 = s5 < 1 ? 1 : 0; // unsigned compare
							}
							sp74[spa4] = s5;
							spa4++;
						} while (spa4 < 3);
					} // 3414c
					else
					{
						spa4 = 0;
						do
						{
							byte s5 = data[spa4 + sp88 + 6];
							sp74[spa4] = s5;
							spa4++;
						} while (spa4 < 3);
					} // 34188
					spa4 = 0;
					writeln(sp74);
					do
					{
						if (sp74[spa4] != 0) // should be 0, 0, 1 first time round
						{
							ushort sp6c = 0xffff;
							ushort sp68 = 0xffff;
							int sp64 = spa4;
							int sp60;
							if (spa4 < 2)
							{
								sp60 = spa4 + 1;
							}
							else
							{
								sp60 = 0;
							}
							writefln("a -%x-%x-%x", sp88, sp64, sp88 + (sp64 * 2));
							ushort sp5c = data.readUshort(sp88 + (sp64 * 2));
							ushort sp58 = data.readUshort(sp88 + (sp60 * 2));
							int sp48, sp44, sp40;
							ushort sp4c, sp50;
							for (int sp54 = 0; sp54 < 2; sp54++)
							{
								if (sp54 != 0)
								{
									// !! LOOKS LIKE THESE READS SHOULD BOTH BE +4 ????
									writefln("b -%x-%x-%x", sp8c, sp58, sp8c + (sp58 * 0x14) + 0x10);
									sp50 = data.readUshort(sp8c + (sp58 * 0x14) + 0x10);
									sp4c = data.readUshort(sp8c + (sp58 * 0x14) + 0x12);
								}
								else
								{
									writefln("c -%x-%x-%x", sp8c, sp5c, sp8c + (sp5c * 0x14) + 0x10);
									sp50 = data.readUshort(sp8c + (sp5c * 0x14) + 0x10);
									sp4c = data.readUshort(sp8c + (sp5c * 0x14) + 0x12);
								} // 342b0
								if (sp50 == 0xffff)
								{
									writefln("d -%x-%x-%x", sp90, sp4c, data.readInt(sp90 + 0x18) + (sp4c * 4));
									sp48 = data.readInt(sp90 + 0x18) + (sp4c * 4);
									sp50 = data.readUshort(sp48);
									sp50 = data.readUshort(sp48 + 2);
								}// 342f0
								sp44 = data.readInt(data.readInt(0x4c) + (sp50 * 4));
								if (sp44 != 0)
								{
									if (sp50 != sp6c || sp4c != sp68)
									{
										sp6c = sp50;
										sp68 = sp4c;
										writefln("n_ %x %x %x", sp44, sp4c, sp44 + (sp4c * 24) + 0x3c);
										sp40 = data.readUshort(sp44 + (sp4c * 24) + 0x3c);
										if (i != 0)
										{
											data.length += 8;
											short sp3c = data.readShort(last_zlib_end + (sp40 * 2));
											short sp38 = data.readShort(last_zlib_end + (sp40 * 2) - 2);
											if (sp3c != 0 && data.readShort(last_zlib_end + (sp40 + sp38 * 2) - 2) == index_value)
											{
												data.writeShort(last_zlib_end + (sp40 * 2) - 2, sp5c);
												data.writeShort(last_zlib_end + (sp40 * 2), sp58);
												data.writeShort(last_zlib_end + (sp40 * 2) + 2, cast(short)(sp38 - 2));
												data.writeShort(last_zlib_end + (sp40 * 2) + 4, cast(short)(sp3c - 2));
												sp40 += 2;
											}// 34460
											else
											{
												data.writeShort(last_zlib_end + (sp40 * 2), index_value);
												data.writeShort(last_zlib_end + (sp40 * 2) + 2, sp5c);
												data.writeShort(last_zlib_end + (sp40 * 2) + 4, sp58);
												data.writeShort(last_zlib_end + (sp40 * 2) + 6, cast(short)0xfffd);
												data.writeShort(last_zlib_end + (sp40 * 2) + 8, cast(short)(sp3c - 4));
												sp40 += 4;
											}// 344e8
											data.writeShort(sp44 + (sp4c * 24) + 0x3c, cast(short)sp40);
										}// 34510
										else
										{
											data.incrementShort(last_zlib_end + (sp40 * 2), 1);
											if (data.readShort(last_zlib_end + (sp40 * 2) + 4) != index_value)
											{
												data.incrementShort(last_zlib_end + (sp40 * 2) + 2, 1);
												data.writeShort(last_zlib_end + (sp40 * 2) + 4, index_value);
											}
										}
									}// 34580
								}// 34580
							}// 34594
						}// 34594
						spa4++;
					} while (spa4 < 3); // 345a0
					sp88 += 0xa;
				}//345cc
			} //345fc
		} // 34610
		// end of big if
		spa8 = spb0;
		do
		{
			for (int s0 = 0; s0 < data.readInt(spa8 + 8); s0++)
			{
				ushort t0 = data.readUshort(spa8 + (s0 * 24) + 0x3c);
				short sp34 = data.readShort(last_zlib_end + (t0 * 2));
				data.writeShort(last_zlib_end + (t0 * 2), cast(short)0xffff);
				data.writeShort(spa8 + (s0 * 24), cast(short)(t0 + sp34));
				data.writeShort(spa8 + (s0 * 24) + 0x3c, cast(short)(t0 - ((data.readInt(spa8 + 0x24) - last_zlib_end) / 2)));
			}// 34710
			spa8 = data.readInt(spa8);
		} while (spa8 != spb0);
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
		//writefln("Inflating zlib block from %x", offset);
		offset += 0x8;

		do
		{
			offset += zlibSize;
			zlibSize = peek!int(binary[offset..offset + 4]);
			offset += 4;
			output ~= cast(ubyte[])uncompress(binary[offset..offset + zlibSize]);

			//writefln("%x inflated", offset);

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