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

import wdc.car, wdc.carFromBinaries,
	   wdc.track,
	   wdc.tools;

class Binary
{

private:
	enum assetsStringOffset = 0xc00;
	enum MY_INSERT_ZONE = 0xFE0000;

	uint carAssetsPointer;
	enum CAR_ASSETS_SIZE = 0x80;
	enum CAR_PALETTE_SIZE = 0x20;
	enum carInsertedPalettes = 8;
	uint carSettingsPointer;
	enum CAR_SETTINGS_SIZE = 0xa0;

	uint trackAssetsPointer;
	enum TRACK_ASSETS_SIZE = 0x44;

	ubyte[] binary;
	ubyte[] curTrackData;

	CarAsset[35] carAssets;

	struct CarAsset
	{
		uint nameRamPointer;
		ubyte[16] blank;
		uint modelZlib;
		uint modelZlibEnd;
		uint textureZlib;
		uint textureZlibEnd;
		uint palette1;
		uint palette1End;
		uint palette2;
		uint palette2End;
		uint palette3;
		uint palette3End;
		ubyte[68] notdone;
	}

public:

	this(string filePath)
	{
		File binaryHandle = File(filePath, "r");
		binary.length = cast(uint)binaryHandle.size;
		binaryHandle.rawRead(binary);
		binaryHandle.close();

		enforceBigEndian();

		carAssetsPointer = binary[0x3e] == 'E' ? 0x81c30 : 0x83620;
		carSettingsPointer = binary[0x3e] == 'E' ? 0x918d0 : 0x0; // TODO Euro
		loadCarAssets();
		trackAssetsPointer = binary[0x3e] == 'E' ? 0x91550 : 0x92f40;

		writefln("Loaded ROM: %s", cast(char[])binary[0x20..0x34]);
		writefln("Version detected as %s", (binary[0x3e] == 'E' ? "NTSC" : "PAL"));
	}

	char[][] getCarList()
	{
		int offset = 0;
		int nameSize;
		uint nameOffset;
		char[][] carNames;
		while(binary[carAssetsPointer + offset] == 0x80)
		{
			nameOffset = peek!int(binary[carAssetsPointer + offset
			                             ..
			                             carAssetsPointer + offset + 4])
						 + assetsStringOffset;
			nameOffset &= 0x0fffffff;
			nameSize = 0;
			while(binary[nameOffset + nameSize] != 0)
			{
				nameSize++;
			}
			carNames ~= cast(char[])binary[nameOffset..(nameOffset + nameSize)];
			offset += CAR_ASSETS_SIZE;
		}
		return carNames;
	}

	Car getCar(int carIndex)
	{
		int carAssetOffset = carAssetsPointer + (CAR_ASSETS_SIZE * carIndex);
		int dataOffset =      peek!int(binary[carAssetOffset + 0x14..carAssetOffset + 0x18]);
		int texturesOffset =  peek!int(binary[carAssetOffset + 0x1C..carAssetOffset + 0x20]);
		int settingsOffset = carSettingsPointer + (CAR_SETTINGS_SIZE * carIndex);
		int palettesAOffset = peek!int(binary[carAssetOffset + 0x24..carAssetOffset + 0x28]);
		int palettesBOffset = peek!int(binary[carAssetOffset + 0x2C..carAssetOffset + 0x30]);
		int palettesCOffset = peek!int(binary[carAssetOffset + 0x34..carAssetOffset + 0x38]);

		return CarFromBinaries.convert(decompressZlibBlock(dataOffset),
		               decompressZlibBlock(texturesOffset),
		               binary[settingsOffset..settingsOffset + CAR_SETTINGS_SIZE],
		               // assuming palettes are always 0x100 in size ...
		               binary[palettesAOffset..palettesAOffset + (carInsertedPalettes * CAR_PALETTE_SIZE)],
		               binary[palettesBOffset..palettesBOffset + (carInsertedPalettes * CAR_PALETTE_SIZE)],
		               binary[palettesCOffset..palettesCOffset + (carInsertedPalettes * CAR_PALETTE_SIZE)]);
	}

	void insertCar(Car car, int carIndex)
	{
		import std.algorithm.comparison : max;
		uint oldSize = carAssets[carIndex].textureZlibEnd - carAssets[carIndex].modelZlib;
		oldSize += oldSize % 4 != 0 ? 4 - (oldSize % 4) : 0;
		uint paddedNewModelSize = car.modelsZlib.length + (car.modelsZlib.length % 4 != 0 ? 4 - (car.modelsZlib.length % 4) : 0);
		uint paddedNewTextureSize = car.texturesZlib.length + (car.texturesZlib.length % 4 != 0 ? 4 - (car.texturesZlib.length % 4) : 0);
		uint newSize = paddedNewModelSize + paddedNewTextureSize;
		uint move;

		if (carAssets[carIndex].modelZlib < MY_INSERT_ZONE)
		{
			move = newSize;
		}
		else
		{
			move = newSize - oldSize;
		}

		if (move < 0)
		{
			binary[carAssets[carIndex].modelZlib..carAssets[carIndex].modelZlib + car.modelsZlib.length] = car.modelsZlib;
			binary[carAssets[carIndex].modelZlib + paddedNewModelSize..carAssets[carIndex].modelZlib + newSize] = car.texturesZlib;
			foreach (ref asset; carAssets[carIndex + 1..$])
			{
				if (asset.modelZlib >= MY_INSERT_ZONE)
				{
					ubyte[] temp = binary[asset.modelZlib..asset.textureZlibEnd].dup;
					binary[asset.modelZlib + move..asset.textureZlibEnd + move] = temp;
					asset.modelZlib += move;
					asset.modelZlibEnd += move;
					asset.textureZlib += move;
					asset.textureZlibEnd += move;
				}
			}
		}
		else if (move > 0)
		{
			foreach_reverse (ref asset; carAssets[carIndex + 1..$])
			{
				if (asset.modelZlib >= MY_INSERT_ZONE)
				{
					ubyte[] temp = binary[asset.modelZlib..asset.textureZlibEnd].dup;
					binary[asset.modelZlib + move..asset.textureZlibEnd + move] = temp;
					asset.modelZlib += move;
					asset.modelZlibEnd += move;
					asset.textureZlib += move;
					asset.textureZlibEnd += move;
				}
			}
			uint highestEnd = 0;
			foreach (asset; carAssets[0..carIndex])
			{
				highestEnd = max(asset.textureZlibEnd, highestEnd);
			}
			if (highestEnd < MY_INSERT_ZONE)
			{
				highestEnd = MY_INSERT_ZONE;
			}
			highestEnd += highestEnd % 4 != 0 ? 4 - (highestEnd % 4) : 0;
			carAssets[carIndex].modelZlib = highestEnd;
			carAssets[carIndex].modelZlibEnd = highestEnd + car.modelsZlib.length;
			carAssets[carIndex].textureZlib = highestEnd + paddedNewModelSize;
			carAssets[carIndex].textureZlibEnd = carAssets[carIndex].textureZlib + car.texturesZlib.length;
		}
		if (binary.length < carAssets[carIndex].textureZlibEnd)
		{
			binary ~= new ubyte[carAssets[carIndex].textureZlibEnd - binary.length];
		}
		// TODO, what if the highest model is not the current one, and it has been moved up? outside binary length
		binary[carAssets[carIndex].modelZlib..carAssets[carIndex].modelZlibEnd] = car.modelsZlib;
		binary[carAssets[carIndex].textureZlib..carAssets[carIndex].textureZlibEnd] = car.texturesZlib;
		binary[carAssets[carIndex].palette1..carAssets[carIndex].palette1End] = car.paletteBinaries[0];
		binary[carAssets[carIndex].palette2..carAssets[carIndex].palette2End] = car.paletteBinaries[1];
		binary[carAssets[carIndex].palette3..carAssets[carIndex].palette3End] = car.paletteBinaries[2];
		// TODO, there are more settings than cars... so is this accurate for all the existing ones?
		uint settingsPointer = carSettingsPointer + (carIndex * CAR_SETTINGS_SIZE);
		binary[settingsPointer..settingsPointer + CAR_SETTINGS_SIZE] = car.settingsBinary;
		updateBinaryCarAssets();
		updateChecksum();
		std.file.write("injectedRome", binary);
	}

	char[][] getTrackList()
	{
		int offset = 0;
		int nameSize;
		uint nameOffset;
		char[][] trackNames;
		while(binary[trackAssetsPointer + offset] == 0x80)
		{
			nameOffset = peek!int(binary[trackAssetsPointer + offset
										 ..
										 trackAssetsPointer + offset + 4])
						 + assetsStringOffset;
			nameOffset &= 0xfffffff;
			nameSize = 0;
			while(binary[nameOffset + nameSize] != 0)
			{
				nameSize++;
			}
			trackNames ~= cast(char[])binary[nameOffset..(nameOffset + nameSize)];
			offset += TRACK_ASSETS_SIZE;
		}
		return trackNames;
	}

	Track getTrack(int trackIndex, int trackVariation)
	{
		// get first zlib from tracks table
		int trackAsset = trackAssetsPointer + (TRACK_ASSETS_SIZE * trackIndex);
		int zlibOffset = readInt(binary, trackAsset + 0x14);
		int firstZlibEnd = readInt(binary, zlibOffset) + zlibOffset;

		curTrackData = decompressZlibBlock(zlibOffset);
		write("primaryZlib", curTrackData);

		Track newTrack = new Track(curTrackData);

		// From here is fnc_34c84:
		// Collision sections
		fnc_334f8(newTrack, trackVariation, firstZlibEnd);

		// Track sections
		fnc_3373c(newTrack, trackVariation, firstZlibEnd);

		//fnc_33a18(data, trackVariation, firstZlibEnd);

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

		write("myTrackData", curTrackData);

		return newTrack;
	}

	void fnc_334f8(Track newTrack, int trackVariation, int firstZlibEnd)
	{
		int inflatedDataPointers = readInt(curTrackData, 0x20);
		// 0x24 inflatedDataPointersCount Count of words at above
		int indicesDescriptorOffsets = readInt(curTrackData, 0x28);
		int indicesDescriptorOffsetsCount = readInt(curTrackData, 0x2c);
		int zlibOffsetTable = readInt(curTrackData, 0x30);

		enforce(trackVariation < indicesDescriptorOffsetsCount,
		        format("Error: Requested track variation (%d) is greater than number available: %d", trackVariation, indicesDescriptorOffsetsCount));

		int indicesDescriptorLocation = readInt(curTrackData, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(curTrackData, indicesDescriptorLocation);
		int indicesLocation = readInt(curTrackData, indicesDescriptorLocation + 4);

		short zlibIndex;
		int zlibOffset;
		int cur_zlib_start;
		int info_offset;
		for (int i = 0; i < indicesCount; i++)
		{
			cur_zlib_start = curTrackData.length;
			zlibIndex = readShort(curTrackData, indicesLocation + (i * 2));
			zlibOffset = readInt(curTrackData, zlibOffsetTable + (zlibIndex * 12));
			info_offset = curTrackData.readInt(zlibOffsetTable + (zlibIndex * 12) + 8);

			newTrack.addBinaryCollisionSection(decompressZlibBlock(firstZlibEnd + zlibOffset), info_offset);
			//curTrackData ~= decompressZlibBlock(firstZlibEnd + zlibOffset); // JAL function_0x2200
			//write(format("u %d", i), decompressZlibBlock(firstZlibEnd + zlibOffset));
		}
	}

	void fnc_3373c(Track newTrack, int trackVariation, int firstZlibEnd)
	{
		// a0 = sp38 = primaryZlib + 0x34
		// a1 = sp3c = end of current data / start of zlib being processed

		// 0x34 Offset to null data that is turned into pointers into the inflated zlibs
		// 0x38 Count of words at above
		int indicesDescriptorOffsets = readInt(curTrackData, 0x3c);
		int indicesDescriptorOffsetsCount = readInt(curTrackData, 0x40);
		int zlibOffsetTable = readInt(curTrackData, 0x44);

		enforce(trackVariation < indicesDescriptorOffsetsCount);

		int indicesDescriptorLocation = readInt(curTrackData, indicesDescriptorOffsets + (trackVariation * 4));
		int indicesCount = readInt(curTrackData, indicesDescriptorLocation);
		int indicesLocation = readInt(curTrackData, indicesDescriptorLocation + 4);

		short zlibIndex;
		int zlibOffset;
		int cur_zlib_start;
		for (int i = 0; i < indicesCount; i++)
		{
			if (curTrackData.length % 0x10 != 0) // These data chunks must be aligned to 0x10
			{
				curTrackData.length += 0x10 - (curTrackData.length % 0x10);
			}
			cur_zlib_start = curTrackData.length;
			zlibIndex = readShort(curTrackData, indicesLocation + (i * 2));
			zlibOffset = readInt(curTrackData, zlibOffsetTable + (zlibIndex * 12));
			curTrackData ~= decompressZlibBlock(firstZlibEnd + zlibOffset);

			//curTrackData.writeInt(0x34 + (zlibIndex * 4), curTrackData.readInt(zlibOffsetTable + (zlibIndex * 0x12) + 8));
			int info_offset = curTrackData.readInt(zlibOffsetTable + (zlibIndex * 12) + 8);
			newTrack.addBinaryTrackSection(decompressZlibBlock(firstZlibEnd + zlibOffset), info_offset);

			//write(format("tp_%.2d_%.8x %.8x", i, zlibOffset, info_offset), decompressZlibBlock(firstZlibEnd + zlibOffset));
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
			//fnc_2060(data, data.readInt(data.readInt(varDataPointers + (zlibIndex * 4)) + 0x20), s3, s3 + s2, s2);
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

	void dumpCarData(int carIndex)
	{
		string workingDir = getcwd();
		string outputDir = workingDir ~ "\\output";
		chdir(outputDir);

		int carAssetOffset = carAssetsPointer + CAR_ASSETS_SIZE * carIndex;
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
					write(format("Car_%.2d_%.8x", carIndex, offset), output);
					offset += output.length;
				}
				else
				{
					writefln("%x not zlib", offset);
				}
		}
		writefln("Car %d data extracted to %s", carIndex, outputDir);
		chdir(workingDir);
	}

	void dumpTrackData(int trackIndex)
	{
		string workingDir = getcwd();
		string outputDir = workingDir ~ "\\output";
		chdir(outputDir);

		int trackAssetOffset = trackAssetsPointer + TRACK_ASSETS_SIZE * trackIndex;
		int offset;

		offset = peek!int(binary[trackAssetOffset + 0x14..trackAssetOffset + 0x14 + 4]);

		auto output = decompressZlibBlock(offset);
		write(format("Track_%.2d_%.8x", trackIndex, offset), output);
		writefln("Track %d data extracted to %s", trackIndex, outputDir);

		chdir(workingDir);
	}

	ubyte[] decompressZlibBlock(int offset)
	{
		enforce(offset % 2 == 0, format("Zlibs are aligned to the nearest halfword, %i is not", offset));
		int blockSize = peek!int(binary[offset..offset + 4]);
		int blockEnd = offset + blockSize;
		//int blockOutputSize = peek!int(binary[offset + 4..offset + 8]);
		int zlibSize = 0;
		ubyte[] output;

		offset += 0x8;
		do
		{
			offset += zlibSize;
			zlibSize = peek!int(binary[offset..offset + 4]);
			offset += 4;
			output ~= cast(ubyte[])uncompress(binary[offset..offset + zlibSize]);

			if (zlibSize % 2 == 1) // Next file will be aligned to short
			{
				zlibSize++;
			}
		} while (offset + zlibSize < blockEnd);

		return output;
	}

private:
	void loadCarAssets()
	{
		ubyte[] assetBytes = binary[carAssetsPointer..carAssetsPointer + (0x80 * carAssets.length)];
		auto structPointer = cast(CarAsset*)assetBytes.ptr;
		carAssets = structPointer[0..carAssets.length];
		foreach (index, ref carAsset; carAssets)
		{
			carAsset.nameRamPointer = swapEndian(carAsset.nameRamPointer);
			carAsset.modelZlib = swapEndian(carAsset.modelZlib);
			carAsset.modelZlibEnd = swapEndian(carAsset.modelZlibEnd);
			carAsset.textureZlib = swapEndian(carAsset.textureZlib);
			carAsset.textureZlibEnd = swapEndian(carAsset.textureZlibEnd);
			carAsset.palette1 = swapEndian(carAsset.palette1);
			carAsset.palette1End = swapEndian(carAsset.palette1End);
			carAsset.palette2 = swapEndian(carAsset.palette2);
			carAsset.palette2End = swapEndian(carAsset.palette2End);
			carAsset.palette3 = swapEndian(carAsset.palette3);
			carAsset.palette3End = swapEndian(carAsset.palette3End);
		}
	}

	void updateBinaryCarAssets()
	{
		int assetLocation;
		foreach (index, asset; carAssets)
		{
			assetLocation = carAssetsPointer + (index * 0x80);
			binary[assetLocation + 0x14..assetLocation + 0x18] = nativeToBigEndian(asset.modelZlib);
			binary[assetLocation + 0x18..assetLocation + 0x1C] = nativeToBigEndian(asset.modelZlibEnd);
			binary[assetLocation + 0x1C..assetLocation + 0x20] = nativeToBigEndian(asset.textureZlib);
			binary[assetLocation + 0x20..assetLocation + 0x24] = nativeToBigEndian(asset.textureZlibEnd);
		}
	}

	void updateChecksum()
	{
		enum CHECKSUM_START = 0x1000;
		enum CHECKSUM_LENGTH = 0x100000;
		enum CHECKSUM_HEADERPOS = 0x10;
		enum CHECKSUM_END = CHECKSUM_START + CHECKSUM_LENGTH;
		enum CHECKSUM_STARTVALUE = 0xf8ca4ddc;

		uint sum1, sum2, offset;
		uint n;
		uint v0, v1, a1, t7, t8, t6, a0, t5, t9;
		uint t1, t2, t3, t4, a2, a3, s0;
		uint checksumLength = CHECKSUM_LENGTH;

		ubyte[] buffer;

		s0 = CHECKSUM_STARTVALUE;
		t2 = CHECKSUM_STARTVALUE;
		t3 = CHECKSUM_STARTVALUE;
		t4 = CHECKSUM_STARTVALUE;
		a2 = CHECKSUM_STARTVALUE;
		a3 = CHECKSUM_STARTVALUE;

		offset = CHECKSUM_START;

		while (offset != CHECKSUM_END) {
			v0 = peek!uint(binary[offset..offset + 4]);
			v1 = a3 + v0;
			if (v1 < a3)
			{
				t2++;
			}
			a1 = v1;
			v1 = v0 & 0x1f;
			t7 = t5 - v1;
			t8 = v0 >> t7;
			t6 = v0 << v1;
			a0 = t6 | t8;
			a3 = a1;
			t3 = t3 ^ v0;
			s0 = s0 + a0;
			if (a2 < v0)
			{
				t9 = a3 ^ v0;
				a2 = t9 ^ a2;
			}
			else
			{
				a2 = a2 ^ a0;
			}
			t7 = v0 ^ s0;
			offset += 4;
			t4 = t7 + t4;
		}
		t6 = a3 ^ t2;
		a3 = t6 ^ t3;
		t8 = s0 ^ a2;
		s0 = t8 ^ t4;

		binary[0x10..0x14] = nativeToBigEndian(a3);
		binary[0x14..0x18] = nativeToBigEndian(s0);
		return;
	}

	void enforceBigEndian()
	{
		//BE 8037 1240
		//BS 3780 4012
		//LE 4012 3780
		switch(binary[0])
		{
			case 0x80:
				writeln("ROM byte order: Big Endian");
				break;
			case 0x40:
				writeln("ROM byte order: Little Endian, switched to Big Endian");
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
				writeln("ROM byte order: Byte Swapped, switched to Big Endian");
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
