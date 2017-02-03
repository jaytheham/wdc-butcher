module wdc.carFromBinaries;

import std.algorithm,
	   wdc.car, wdc.tools,
	   gfm.math;

static class CarFromBinaries
{
	public static Car convert(ubyte[] binary, ubyte[] textures, ubyte[] settings, ubyte[] palettesA, ubyte[] palettesB, ubyte[] palettesC)
	{
		Car car = new Car();
		car.modelsBinary = binary;
		car.texturesBinary = textures;
		car.paletteBinaries[0] = palettesA;
		car.paletteBinaries[1] = palettesB;
		car.paletteBinaries[2] = palettesC;

		car.unknown1 = binary.readFloat(0x8);
		car.inCarCameraYOffset = binary.readFloat(0xC);
		car.wheelOrigins = [vec3f(binary.readFloat(0x18), binary.readFloat(0x1C), binary.readFloat(0x14)),
		                    vec3f(binary.readFloat(0x24), binary.readFloat(0x28), binary.readFloat(0x20)),
		                    vec3f(binary.readFloat(0x30), binary.readFloat(0x34), binary.readFloat(0x2C)),
		                    vec3f(binary.readFloat(0x3C), binary.readFloat(0x40), binary.readFloat(0x38))];
		car.lightOrigins = [vec3f(binary.readFloat(0x48), binary.readFloat(0x4C), binary.readFloat(0x44)),
		                    vec3f(binary.readFloat(0x54), binary.readFloat(0x58), binary.readFloat(0x50)),
		                    vec3f(binary.readFloat(0x60), binary.readFloat(0x64), binary.readFloat(0x5C)),
		                    vec3f(binary.readFloat(0x6C), binary.readFloat(0x70), binary.readFloat(0x68))];

		parseBinarySettings(settings, car);

		parseBinaryTextures(binary, textures, car);

		parseBinaryPalettes(palettesA, car.paletteSets[0]);
		parseBinaryPalettes(palettesB, car.paletteSets[1]);
		parseBinaryPalettes(palettesC, car.paletteSets[2]);

		parseBinaryFixedPalettes(binary, car);

		parseBinaryModels(binary, car);
		return car;
	}

	private static void parseBinarySettings(ubyte[] settings, Car car)
	{
		import std.bitmanip : read;
		import std.stdio;
		foreach (ref value; car.settings)
		{
			value = settings.read!float();
			writeln(value);
		}
	}

	private static void parseBinaryTextures(ubyte[] binary, ubyte[] binaryTextures, Car car)
	{
		int modelToTexturePointers = binary.readInt(0xA0);
		int modelToTextureCount = binary.readInt(0xA8);

		int textureDescriptorPointers = binary.readInt(0xB4);
		int textureDescriptorCount = binary.readInt(0xB8);

		int descriptorPointer;
		int textureDescriptorSize, actualTextureSize;
		int destination, nextDestination, sourcePosition = 0;

		car.modelToTextureMap.length = modelToTextureCount;
		car.textures.length = textureDescriptorCount;

		foreach(tIndex; 0..textureDescriptorCount)
		{
			descriptorPointer = binary.readInt(textureDescriptorPointers + (tIndex * 4));
			actualTextureSize = textureDescriptorSize = (((binary.readInt(descriptorPointer + 0x14) >> 12) & 0xFFF) + 1) << 1;
			if (textureDescriptorSize < Car.TEXTURE_SIZE_BYTES)
			{
				destination = binary.readInt(descriptorPointer + 4);
				nextDestination = binary.readInt(descriptorPointer + 0x20 + 4);
				actualTextureSize = nextDestination - destination;
			}
			car.textures[tIndex] = binaryTextures[sourcePosition..sourcePosition + actualTextureSize];
			if (actualTextureSize == Car.TEXTURE_SIZE_BYTES)
			{
				wordSwapOddRows(car.textures[tIndex], Car.TEXTURE_WIDTH_BYTES, Car.TEXTURE_HEIGHT_BYTES);
			}
			sourcePosition += textureDescriptorSize;
			foreach(mIndex; 0..modelToTextureCount)
			{
				if (binary.readInt(modelToTexturePointers + (mIndex * 4)) == descriptorPointer)
				{
					car.modelToTextureMap[mIndex] = tIndex;
				}
			}
		}
	}

	private static void parseBinaryPalettes(ubyte[] binaryPalette,
		ref Car.Colour[Car.COLOURS_PER_PALETTE][Car.PALETTES_PER_SET] destination)
	{
		foreach(index; 0..(Car.COLOURS_PER_PALETTE * Car.PALETTES_PER_SET))
		{
			destination[index / Car.COLOURS_PER_PALETTE][index % Car.COLOURS_PER_PALETTE] =
				Car.Colour(binaryPalette.readUshort(index * 2));
		}
	}

	private static void parseBinaryFixedPalettes(ubyte[] binary, Car car)
	{
		int insertedPalettePointer = 0x7C;

		foreach(i; 0..Car.PALETTES_PER_SET)
		{
			car.insertedPaletteIndices[i] = binary.readInt(insertedPalettePointer);
			insertedPalettePointer += 4;
		}

		for(int palettePointer = 0x398;; palettePointer += 0x20)
		{
			if (binary.readInt(palettePointer) != 0)
			{
				// fixed palette
				car.fixedPalettes ~= new Car.Colour[Car.COLOURS_PER_PALETTE];
				foreach(i; 0..Car.COLOURS_PER_PALETTE)
				{
					car.fixedPalettes[$ - 1][i] = Car.Colour(binary.readUshort(palettePointer + (i * 2)));
				}
			}
			else if (canFind(car.insertedPaletteIndices[], palettePointer))
			{
				// inserted palette
				car.fixedPalettes ~= null;
			}
			else
			{
				break;
			}
		}
		// Turn pointers into palette block indices
		foreach(i; 0..Car.PALETTES_PER_SET)
		{
			car.insertedPaletteIndices[i] = (car.insertedPaletteIndices[i] - 0x398) / 0x20;
		}
	}

	private static void parseBinaryModels(ubyte[] binary, Car car)
	{
		int nextmodelSectionAddressSource = 0xF4;
		int modelSectionAddress = binary.readInt(nextmodelSectionAddressSource);
		int previousmodelSectionAddress = 0;
		int verticesPointer = 0, normalsPointer, polygonPointer, verticesCount, normalsCount, polygonsCount;
		int currentModelNum = -1;
		Car.Model currentModel;
		Car.ModelSection currentModelSection;
		while (modelSectionAddress != 0)
		{
			if (binary.readInt(modelSectionAddress) == modelSectionAddress ||
				modelSectionAddress == previousmodelSectionAddress)
			{
				nextmodelSectionAddressSource += 0x10;
				modelSectionAddress = binary.readInt(nextmodelSectionAddressSource);
				continue;
			}
			if (binary.readInt(modelSectionAddress) != verticesPointer)
			{
				verticesPointer = binary.readInt(modelSectionAddress);
				verticesCount   = binary.readInt(modelSectionAddress + 4);
				normalsPointer  = binary.readInt(modelSectionAddress + 32);
				normalsCount    = binary.readInt(modelSectionAddress + 36);

				currentModel = Car.Model(new vec3s[verticesCount], new vec3b[normalsCount]);

				foreach(i; 0..verticesCount)
				{
					currentModel.vertices[i] = vec3s(binary.readShort(verticesPointer + 2 + (i * 6)),
					                                 binary.readShort(verticesPointer + 4 + (i * 6)),
					                                 binary.readShort(verticesPointer + 0 + (i * 6)));
				}
				foreach(i; 0..normalsCount)
				{
					currentModel.normals[i] = vec3b(cast(byte)binary[normalsPointer + 1 + (i * 3)],
					                                cast(byte)binary[normalsPointer + 2 + (i * 3)],
					                                cast(byte)binary[normalsPointer + 0 + (i * 3)]);
				}
				currentModelNum++;
				car.models[currentModelNum] = currentModel;
			}
			polygonPointer = binary.readInt(modelSectionAddress + 8);
			polygonsCount   = binary.readInt(modelSectionAddress + 12);
			currentModelSection = Car.ModelSection(new Car.Polygon[polygonsCount]);
			foreach (i; 0..polygonsCount)
			{
				currentModelSection.polygons[i] =
					Car.Polygon([binary.readUshort(polygonPointer + 8),
					             binary.readUshort(polygonPointer + 10),
					             binary.readUshort(polygonPointer + 12),
					             binary.readUshort(polygonPointer + 14)],
					            [vec2b(cast(byte)binary[polygonPointer + 16],
					                   cast(byte)binary[polygonPointer + 17]),
					             vec2b(cast(byte)binary[polygonPointer + 18],
					                   cast(byte)binary[polygonPointer + 19]),
					             vec2b(cast(byte)binary[polygonPointer + 20],
					                   cast(byte)binary[polygonPointer + 21]),
					             vec2b(cast(byte)binary[polygonPointer + 22],
					                   cast(byte)binary[polygonPointer + 23])],
					            [binary.readUshort(polygonPointer + 24),
					             binary.readUshort(polygonPointer + 26),
					             binary.readUshort(polygonPointer + 28),
					             binary.readUshort(polygonPointer + 30)]
					           );
				polygonPointer += 0x20;
			}
			car.models[currentModelNum].modelSections ~= currentModelSection;

			nextmodelSectionAddressSource += 0x10;
			previousmodelSectionAddress = modelSectionAddress;
			modelSectionAddress = binary.readInt(nextmodelSectionAddressSource);
		}
	}
}