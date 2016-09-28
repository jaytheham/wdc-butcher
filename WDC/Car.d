module wdc.car;

import std.stdio,	   std.array,	   std.file,
	   std.format,	   std.bitmanip,   std.typecons,
	   std.algorithm,
	   camera,
	   gfm.math,	   gfm.opengl,
	   wdc.tools,	   wdc.drawable,   wdc.renderer,
	   wdc.carRenderer;
// Convert Binary files from the ROM or 3D model files into a simple intermediate format
// from which it can output ROM compatible binaries or 3D models
class Car : Drawable
{
	ubyte[] binaryData;
	ubyte[] binaryTextures;
	ubyte[] binaryPalettes1;
	ubyte[] binaryPalettes2;
	ubyte[] binaryPalettes3;

	private
	{
		CarRenderer renderer;

		enum PALETTE_COLOUR_COUNT = 0x10;
		enum PALETTE_COUNT = 8;

		float unknown1;
		float carCameraYOffset;
		vec3f[4] wheelOrigins;
		vec3f[4] lightOrigins;
		uint[] modelToTextureMap;
		ubyte[][] bodyTextures;
		Colour[][] fixedPalettes;
		Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] palettesA;
		Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] palettesB;
		Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] palettesC;
		Model[] models;

		union Colour
		{
			ushort whole;
			mixin(bitfields!(
				ubyte, "alpha",		1,
				ubyte,	"b",		5,
				ubyte,	"g",		5,
				ubyte,	"r",		5));
		}

		struct Model
		{
			Vertex[] vertices;
			Normal[] normals;
			ModelSection[] modelSections;
		}

		struct Vertex
		{
			short Z;
			short X;
			short Y;
		}

		struct Normal
		{
			byte Z;
			byte X;
			byte Y;
		}

		struct ModelSection
		{
			Polygon[] polygons;
		}

		struct Polygon
		{
			ushort[4] vertexIndices;
			TextureCoordinate[4] textureCoordinates;
			ushort[4] normalIndices;
		}

		struct TextureCoordinate
		{
			byte U;
			byte V;
		}
	}

	this(ubyte[] dataBlob, ubyte[] textureSource, ubyte[] inPalettesA, ubyte[] inPalettesB, ubyte[] inPalettesC)
	{
		binaryData = dataBlob;
		binaryTextures = textureSource;
		binaryPalettes1 = inPalettesA;
		binaryPalettes2 = inPalettesB;
		binaryPalettes3 = inPalettesC;

		unknown1 = binaryData.readFloat(0x8);
		carCameraYOffset = binaryData.readFloat(0xC);
		wheelOrigins = [vec3f(binaryData.readFloat(0x14),binaryData.readFloat(0x18),binaryData.readFloat(0x1C)),
		                vec3f(binaryData.readFloat(0x20),binaryData.readFloat(0x24),binaryData.readFloat(0x28)),
		                vec3f(binaryData.readFloat(0x2C),binaryData.readFloat(0x30),binaryData.readFloat(0x34)),
		                vec3f(binaryData.readFloat(0x38),binaryData.readFloat(0x3C),binaryData.readFloat(0x40))];
		lightOrigins = [vec3f(binaryData.readFloat(0x44),binaryData.readFloat(0x48),binaryData.readFloat(0x4C)),
		                vec3f(binaryData.readFloat(0x50),binaryData.readFloat(0x54),binaryData.readFloat(0x58)),
		                vec3f(binaryData.readFloat(0x5C),binaryData.readFloat(0x60),binaryData.readFloat(0x64)),
		                vec3f(binaryData.readFloat(0x68),binaryData.readFloat(0x6C),binaryData.readFloat(0x70))];

		parseBinaryTextures();

		parseBinaryPalettes(inPalettesA, palettesA);
		parseBinaryPalettes(inPalettesB, palettesB);
		parseBinaryPalettes(inPalettesC, palettesC);

		parseBinaryFixedPalettes();

		parseBinaryModels();
	}

	void setupDrawing(OpenGL opengl)
	{
		renderer = new CarRenderer(this, opengl);
	}

	void draw(Camera camera, char[] keys)
	{
		renderer.draw(camera, keys);
	}

	private void parseBinaryTextures()
	{
		int bodyModelTexturePointers = binaryData.readInt(0xA0);
		int bodyModelTextureCount = binaryData.readInt(0xA8);
		modelToTextureMap.length = bodyModelTextureCount;

		int textureDescriptorPointers = binaryData.readInt(0xB4);
		int textureDescriptorCount = binaryData.readInt(0xB8);
		int descriptorLocation;
		int textureSize;
		int texturePosition = 0;

		bodyTextures.length = textureDescriptorCount;

		foreach(index; 0..textureDescriptorCount)
		{
			descriptorLocation = binaryData.readInt(textureDescriptorPointers + (index * 4));
			textureSize = (((binaryData.readInt(descriptorLocation + 0x14) >> 12) & 0xFFF) + 1) << 1;
			bodyTextures[index] = binaryTextures[texturePosition..texturePosition + textureSize];
			texturePosition += textureSize;

			foreach(mIndex; 0..bodyModelTextureCount)
			{
				if (binaryData.readInt(bodyModelTexturePointers + (mIndex * 4)) == descriptorLocation)
				{
					modelToTextureMap[mIndex] = index;
				}
			}
		}
		// The four "wheel texture descriptors" that come after the main lot are
		// always the same as the last four from the main lot, so can just copy them
	}

	private void parseBinaryPalettes(ubyte[] binaryPaletteSource, Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] destination)
	{
		foreach(index; 0..(PALETTE_COLOUR_COUNT * PALETTE_COUNT))
		{
			destination[index / PALETTE_COLOUR_COUNT][index % PALETTE_COLOUR_COUNT] = Colour(binaryPaletteSource.readUshort(index * 2));
		}
	}

	private void parseBinaryFixedPalettes()
	{
		int[PALETTE_COUNT] insertedPalettePointers;
		int palettePointerPointer = 0x7C;

		foreach(i; 0..PALETTE_COUNT)
		{
			insertedPalettePointers[i] = binaryData.readInt(palettePointerPointer);
			palettePointerPointer += 4;
		}

		for(int palettePointer = 0x398;; palettePointer += 0x20)
		{
			if (binaryData.readInt(palettePointer) != 0)
			{
				// fixed palette
				fixedPalettes ~= new Colour[PALETTE_COLOUR_COUNT];
				foreach(i; 0..PALETTE_COLOUR_COUNT)
				{
					fixedPalettes[$ - 1][i] = Colour(binaryData.readUshort(palettePointer + (i * 2)));
				}
			}
			else if (canFind(insertedPalettePointers[], palettePointer))
			{
				// inserted palette
				fixedPalettes ~= null;
			}
			else
			{
				break;
			}
		}
	}

	private void parseBinaryModels()
	{
		int nextModelSectionPointerSource = 0xF4;
		int modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
		int verticesPointer = 0, normalsPointer, polygonsPointer, verticesCount, normalsCount, polygonsCount;
		Model currentModel;
		ModelSection currentModelSection;
		while(modelSectionPointer != 0)
		{
			if (binaryData.readInt(modelSectionPointer) != verticesPointer)
			{
				verticesPointer = binaryData.readInt(modelSectionPointer);
				verticesCount   = binaryData.readInt(modelSectionPointer + 4);
				normalsPointer  = binaryData.readInt(modelSectionPointer + 32);
				normalsCount    = binaryData.readInt(modelSectionPointer + 36);

				models ~= Model(new Vertex[verticesCount], new Normal[normalsCount]);
				currentModel = models[$ - 1];

				foreach(i; 0..verticesCount)
				{
					currentModel.vertices[i] = Vertex(binaryData.readShort(verticesPointer + 0 + (i * 6)),
					                                  binaryData.readShort(verticesPointer + 2 + (i * 6)),
					                                  binaryData.readShort(verticesPointer + 4 + (i * 6)));
				}
				foreach(i; 0..normalsCount)
				{
					currentModel.normals[i] = Normal(cast(byte)binaryData[normalsPointer + 0 + (i * 3)],
					                                 cast(byte)binaryData[normalsPointer + 1 + (i * 3)],
					                                 cast(byte)binaryData[normalsPointer + 2 + (i * 3)]);
				}
			}
			polygonsPointer = binaryData.readInt(modelSectionPointer + 8);
			polygonsCount   = binaryData.readInt(modelSectionPointer + 12);

			currentModel.modelSections ~= ModelSection(new Polygon[polygonsCount]);
			currentModelSection = currentModel.modelSections[$ - 1];
			foreach (i; 0..polygonsCount)
			{
				currentModelSection.polygons[i] = Polygon([binaryData.readUshort(polygonsPointer + 8  + (i * 0x20)),
				                                           binaryData.readUshort(polygonsPointer + 10 + (i * 0x20)),
				                                           binaryData.readUshort(polygonsPointer + 12 + (i * 0x20)),
				                                           binaryData.readUshort(polygonsPointer + 14 + (i * 0x20))],
				                                          [TextureCoordinate(cast(byte)binaryData[polygonsPointer + 16 + (i * 0x20)], cast(byte)binaryData[polygonsPointer + 17 + (i * 0x20)]),
				                                           TextureCoordinate(cast(byte)binaryData[polygonsPointer + 18 + (i * 0x20)], cast(byte)binaryData[polygonsPointer + 19 + (i * 0x20)]),
				                                           TextureCoordinate(cast(byte)binaryData[polygonsPointer + 20 + (i * 0x20)], cast(byte)binaryData[polygonsPointer + 21 + (i * 0x20)]),
				                                           TextureCoordinate(cast(byte)binaryData[polygonsPointer + 22 + (i * 0x20)], cast(byte)binaryData[polygonsPointer + 23 + (i * 0x20)])],
				                                          [binaryData.readUshort(polygonsPointer + 24 + (i * 0x20)),
				                                           binaryData.readUshort(polygonsPointer + 26 + (i * 0x20)),
				                                           binaryData.readUshort(polygonsPointer + 28 + (i * 0x20)),
				                                           binaryData.readUshort(polygonsPointer + 30 + (i * 0x20))]
				                                         );
			}

			nextModelSectionPointerSource += 0x10;
			modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
		}
	}
}
