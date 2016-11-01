module wdc.carFromBinaries;

import std.algorithm,
	   wdc.car, wdc.tools,
	   gfm.math;

static class CarFromBinaries
{
	public static Car convert(ubyte[] binary, ubyte[] binaryTextures, ubyte[] inPalettesA, ubyte[] inPalettesB, ubyte[] inPalettesC)
	{
		Car car = new Car();
		car.binaryData = binary;
		car.binaryTextures = binaryTextures;
		car.binaryPalettes1 = inPalettesA;
		car.binaryPalettes2 = inPalettesB;
		car.binaryPalettes3 = inPalettesC;

		car.unknown1 = binary.readFloat(0x8);
		car.carCameraYOffset = binary.readFloat(0xC);
		car.wheelOrigins = [vec3f(binary.readFloat(0x18), binary.readFloat(0x1C), binary.readFloat(0x14)),
		                    vec3f(binary.readFloat(0x24), binary.readFloat(0x28), binary.readFloat(0x20)),
		                    vec3f(binary.readFloat(0x30), binary.readFloat(0x34), binary.readFloat(0x2C)),
		                    vec3f(binary.readFloat(0x3C), binary.readFloat(0x40), binary.readFloat(0x38))];
		car.lightOrigins = [vec3f(binary.readFloat(0x48), binary.readFloat(0x4C), binary.readFloat(0x44)),
		                    vec3f(binary.readFloat(0x54), binary.readFloat(0x58), binary.readFloat(0x50)),
		                    vec3f(binary.readFloat(0x60), binary.readFloat(0x64), binary.readFloat(0x5C)),
		                    vec3f(binary.readFloat(0x6C), binary.readFloat(0x70), binary.readFloat(0x68))];

		parseBinaryTextures(binary, binaryTextures, car);

		parseBinaryPalettes(inPalettesA, car.palettes[0]);
		parseBinaryPalettes(inPalettesB, car.palettes[1]);
		parseBinaryPalettes(inPalettesC, car.palettes[2]);

		parseBinaryFixedPalettes(binary, car);

		parseBinaryModels(binary, car);
		return car;
	}

	private static void parseBinaryTextures(ubyte[] binaryData, ubyte[] binaryTextures, Car car)
	{
		import std.stdio;
		int modelToTexturePointers = binaryData.readInt(0xA0);
		int modelToTextureCount = binaryData.readInt(0xA8);
		//modelToTextureMap.length = modelToTextureCount;

		int textureDescriptorPointers = binaryData.readInt(0xB4);
		int textureDescriptorCount = binaryData.readInt(0xB8);
		int descriptorLocation;
		int textureSizeInBytes;
		int texturePosition = 0;

		car.textures.length = textureDescriptorCount;
		
		foreach(index; 0..textureDescriptorCount)
		{
			descriptorLocation = binaryData.readInt(textureDescriptorPointers + (index * 4));
			textureSizeInBytes = (((binaryData.readInt(descriptorLocation + 0x14) >> 12) & 0xFFF) + 1) << 1;
			car.textures[index] = binaryTextures[texturePosition..texturePosition + textureSizeInBytes];
			if (textureSizeInBytes > 8)
			{
				wordSwapOddRows(car.textures[index], 40, 38);
			}
			texturePosition += textureSizeInBytes;
			
			foreach(mIndex; 0..modelToTextureCount)
			{
				if (binaryData.readInt(modelToTexturePointers + (mIndex * 4)) == descriptorLocation)
				{
					writeln(car.modelToTextureMap.length, " ", mIndex);
					car.modelToTextureMap[mIndex] = index;
				}
			}
		}
	}

	private static void wordSwapOddRows(ref ubyte[] rawTexture, int bytesWide, int textureHeight)
	{
		ubyte[4] tempBytes;
		int curOffset;
		
		assert(bytesWide % 8 == 0, "ONLY WORKS FOR TEXTURES THAT ARE A MULTIPLE OF 16 WIDE!");

		for (int row = 0; row < textureHeight; row++)
		{
			if (row % 2 == 1)
			{
				curOffset = row * bytesWide;
				for (int byteNum = 0; byteNum < bytesWide; byteNum += 8)
				{
					tempBytes[] = rawTexture[curOffset + byteNum..curOffset + byteNum + 4];
					rawTexture[curOffset + byteNum..curOffset + byteNum + 4] = 
						rawTexture[curOffset + byteNum + 4..curOffset + byteNum + 8];
					rawTexture[curOffset + byteNum + 4..curOffset + byteNum + 8] = tempBytes[];
				}
			}
		}
	}

	private static void parseBinaryPalettes(ubyte[] binaryPaletteSource, ref Car.Colour[Car.COLOURS_PER_PALETTE][Car.PALETTES_PER_SET] destination)
	{
		foreach(index; 0..(Car.COLOURS_PER_PALETTE * Car.PALETTES_PER_SET))
		{
			destination[index / Car.COLOURS_PER_PALETTE][index % Car.COLOURS_PER_PALETTE] = Car.Colour(binaryPaletteSource.readUshort(index * 2));
		}
	}

	private static void parseBinaryFixedPalettes(ubyte[] binaryData, Car car)
	{
		int palettePointerPointer = 0x7C;

		foreach(i; 0..Car.PALETTES_PER_SET)
		{
			car.insertedPaletteIndices[i] = binaryData.readInt(palettePointerPointer);
			palettePointerPointer += 4;
		}

		for(int palettePointer = 0x398;; palettePointer += 0x20)
		{
			if (binaryData.readInt(palettePointer) != 0)
			{
				// fixed palette
				car.fixedPalettes ~= new Car.Colour[Car.COLOURS_PER_PALETTE];
				foreach(i; 0..Car.COLOURS_PER_PALETTE)
				{
					car.fixedPalettes[$ - 1][i] = Car.Colour(binaryData.readUshort(palettePointer + (i * 2)));
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
		// set pointers relative to palette block index
		foreach(i; 0..Car.PALETTES_PER_SET)
		{
			car.insertedPaletteIndices[i] = (car.insertedPaletteIndices[i] - 0x398) / 0x20;
		}
	}

	private static void parseBinaryModels(ubyte[] binaryData, Car car)
	{
		int nextModelSectionPointerSource = 0xF4;
		int modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
		int previousModelSectionPointer = 0;
		int verticesPointer = 0, normalsPointer, polygonsPointer, verticesCount, normalsCount, polygonsCount;
		int currentModelNum = -1;
		Car.Model currentModel;
		Car.ModelSection currentModelSection;
		while (modelSectionPointer != 0)
		{
			if (binaryData.readInt(modelSectionPointer) == modelSectionPointer
				|| modelSectionPointer == previousModelSectionPointer)
			{
				nextModelSectionPointerSource += 0x10;
				modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
				continue;
			}
			if (binaryData.readInt(modelSectionPointer) != verticesPointer)
			{
				verticesPointer = binaryData.readInt(modelSectionPointer);
				verticesCount   = binaryData.readInt(modelSectionPointer + 4);
				normalsPointer  = binaryData.readInt(modelSectionPointer + 32);
				normalsCount    = binaryData.readInt(modelSectionPointer + 36);

				currentModel = Car.Model(new Car.Vertex[verticesCount], new Car.Normal[normalsCount]);

				foreach(i; 0..verticesCount)
				{
					currentModel.vertices[i] = Car.Vertex(binaryData.readShort(verticesPointer + 0 + (i * 6)),
					                                  binaryData.readShort(verticesPointer + 2 + (i * 6)),
					                                  binaryData.readShort(verticesPointer + 4 + (i * 6)));
				}
				foreach(i; 0..normalsCount)
				{
					currentModel.normals[i] = Car.Normal(cast(byte)binaryData[normalsPointer + 0 + (i * 3)],
					                                 cast(byte)binaryData[normalsPointer + 1 + (i * 3)],
					                                 cast(byte)binaryData[normalsPointer + 2 + (i * 3)]);
				}
				currentModelNum++;
				car.models[currentModelNum] = currentModel;
			}
			polygonsPointer = binaryData.readInt(modelSectionPointer + 8);
			polygonsCount   = binaryData.readInt(modelSectionPointer + 12);
			currentModelSection = Car.ModelSection(new Car.Polygon[polygonsCount]);
			foreach (i; 0..polygonsCount)
			{
				currentModelSection.polygons[i] =
					Car.Polygon([binaryData.readUshort(polygonsPointer + 8  + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 10 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 12 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 14 + (i * 0x20))],
                            [Car.TextureCoordinate(cast(byte)binaryData[polygonsPointer + 16 + (i * 0x20)],
                            	                   cast(byte)binaryData[polygonsPointer + 17 + (i * 0x20)]),
                             Car.TextureCoordinate(cast(byte)binaryData[polygonsPointer + 18 + (i * 0x20)],
                             	                   cast(byte)binaryData[polygonsPointer + 19 + (i * 0x20)]),
                             Car.TextureCoordinate(cast(byte)binaryData[polygonsPointer + 20 + (i * 0x20)],
                             	                   cast(byte)binaryData[polygonsPointer + 21 + (i * 0x20)]),
                             Car.TextureCoordinate(cast(byte)binaryData[polygonsPointer + 22 + (i * 0x20)],
                             	                   cast(byte)binaryData[polygonsPointer + 23 + (i * 0x20)])],
                            [binaryData.readUshort(polygonsPointer + 24 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 26 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 28 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 30 + (i * 0x20))]
                           );
			}
			car.models[currentModelNum].modelSections ~= currentModelSection;

			nextModelSectionPointerSource += 0x10;
			previousModelSectionPointer = modelSectionPointer;
			modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
		}
	}
}