module wdc.car;

import std.stdio,
	   std.array,
	   std.file,
	   std.format,
	   std.bitmanip,
	   std.typecons,
	   std.algorithm,
	   camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.tools,
	   wdc.drawable,
	   wdc.renderer,
	   wdc.carRenderer,
	   wdc.microcode;
// Car should accept either:
//  Binary files from the ROM
//  3D model files
// and convert them into an understandable, intermediate format from which it can output ROM compatible binaries
// or 3D models
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

		Header header;

		enum PALETTE_COLOUR_COUNT = 0x10;
		enum PALETTE_COUNT = 8;

		struct Header
		{
			float unknown1;
			float carCameraYOffset;
			vec3f[4] wheelOrigins;
			vec3f[4] lightOrigins;
			uint[] bodyModelToTextureMap;
			ubyte[][] bodyTextures;
			Colour[][] fixedPalettes;
			Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] palettesA;
			Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] palettesB;
			Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] palettesC;
			Model[] models;
		}

		union Colour
		{
			ushort whole;
			mixin(bitfields!(
				ubyte, "alpha",		1,
				ubyte,	"b",		5,
				ubyte,	"g",		5,
				ubyte,	"r",		5));

			string toString()
			{
				return format("%.4X", whole);
			}
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
			// info
		}

		struct Polygon
		{
			ushort[4] vertexIndices;
			UV[4] uVs;
			ushort[4] normalIndices;
		}

		struct UV
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

		header = Header(binaryData.readFloat(0x8),
		                binaryData.readFloat(0xC),
		                [vec3f(binaryData.readFloat(0x14),binaryData.readFloat(0x18),binaryData.readFloat(0x1C)),
		                vec3f(binaryData.readFloat(0x20),binaryData.readFloat(0x24),binaryData.readFloat(0x28)),
		                vec3f(binaryData.readFloat(0x2C),binaryData.readFloat(0x30),binaryData.readFloat(0x34)),
		                vec3f(binaryData.readFloat(0x38),binaryData.readFloat(0x3C),binaryData.readFloat(0x40))],
		                [vec3f(binaryData.readFloat(0x44),binaryData.readFloat(0x48),binaryData.readFloat(0x4C)),
		                vec3f(binaryData.readFloat(0x50),binaryData.readFloat(0x54),binaryData.readFloat(0x58)),
		                vec3f(binaryData.readFloat(0x5C),binaryData.readFloat(0x60),binaryData.readFloat(0x64)),
		                vec3f(binaryData.readFloat(0x68),binaryData.readFloat(0x6C),binaryData.readFloat(0x70))]);

		int bodyModelTexturePointers = binaryData.readInt(0xA0);
		int bodyModelTextureCount = binaryData.readInt(0xA8);
		header.bodyModelToTextureMap.length = bodyModelTextureCount;

		int textureDescriptorPointers = binaryData.readInt(0xB4);
		int textureDescriptorCount = binaryData.readInt(0xB8);
		int descriptorLocation;
		int textureSize;
		int texturePosition = 0;

		header.bodyTextures.length = textureDescriptorCount;

		foreach(index; 0..textureDescriptorCount)
		{
			descriptorLocation = binaryData.readInt(textureDescriptorPointers + (index * 4));
			textureSize = (((binaryData.readInt(descriptorLocation + 0x14) >> 12) & 0xFFF) + 1) << 1;
			header.bodyTextures[index] = binaryTextures[texturePosition..texturePosition + textureSize];
			texturePosition += textureSize;

			foreach(mIndex; 0..bodyModelTextureCount)
			{
				if (binaryData.readInt(bodyModelTexturePointers + (mIndex * 4)) == descriptorLocation)
				{
					header.bodyModelToTextureMap[mIndex] = index;
				}
			}
		}

		// The four "wheel texture descriptors" that come after the main lot are
		// always the same as the last four from the main lot, so can just copy them

		binaryPalettesToPalettes(inPalettesA, header.palettesA);
		binaryPalettesToPalettes(inPalettesB, header.palettesB);
		binaryPalettesToPalettes(inPalettesC, header.palettesC);

		int[PALETTE_COUNT] insertedPalettePointers;
		int palettePointerPointer = 0x7C;

		foreach(index; 0..PALETTE_COUNT)
		{
			insertedPalettePointers[index] = binaryData.readInt(palettePointerPointer);
			palettePointerPointer += 4;
		}

		int palettePointer = 0x398;
		for(;; palettePointer += 0x20)
		{
			if (binaryData.readInt(palettePointer) != 0)
			{
				// fixed palette
				header.fixedPalettes ~= new Colour[PALETTE_COLOUR_COUNT];
				foreach(index; 0..PALETTE_COLOUR_COUNT)
				{
					header.fixedPalettes[$ - 1][index] = Colour(binaryData.readUshort(palettePointer + (index * 2)));
				}
			}
			else if (canFind(insertedPalettePointers[], palettePointer))
			{
				// inserted palette
				header.fixedPalettes ~= null;
			}
			else
			{
				break;
			}
		}

		int nextModelSectionPointer = 0xF4;
		int modelSectionPointer = binaryData.readInt(nextModelSectionPointer);
		int verticesPointer = 0, normalsPointer, polygonsPointer, verticesCount, normalsCount, polygonsCount;
		while(modelSectionPointer != 0)
		{
			if (binaryData.readInt(modelSectionPointer) != verticesPointer)
			{
				verticesPointer = binaryData.readInt(modelSectionPointer);
				verticesCount =   binaryData.readInt(modelSectionPointer + 4);
				normalsPointer =  binaryData.readInt(modelSectionPointer + 32);
				normalsCount =    binaryData.readInt(modelSectionPointer + 36);

				header.models ~= Model(new Vertex[verticesCount], new Normal[normalsCount]);
				foreach(i; 0..verticesCount)
				{
					header.models[$ - 1].vertices[i] = Vertex(binaryData.readShort(verticesPointer + (i * 6)),
					                                          binaryData.readShort(verticesPointer + 2 + (i * 6)),
					                                          binaryData.readShort(verticesPointer + 4 + (i * 6)));
				}
				foreach(i; 0..normalsCount)
				{
					header.models[$ - 1].normals[i] = Normal(cast(byte)binaryData[normalsPointer + (i * 3)],
					                                         cast(byte)binaryData[normalsPointer + 1 + (i * 3)],
					                                         cast(byte)binaryData[normalsPointer + 2 + (i * 3)]);
				}
			}
			polygonsPointer = binaryData.readInt(modelSectionPointer + 8);
			polygonsCount =   binaryData.readInt(modelSectionPointer + 12);

			// TODO polygons

			nextModelSectionPointer += 0x10;
			modelSectionPointer = binaryData.readInt(nextModelSectionPointer);
		}
	}

	void binaryPalettesToPalettes(ubyte[] source, Colour[PALETTE_COLOUR_COUNT][PALETTE_COUNT] destination)
	{
		foreach(index; 0..(PALETTE_COLOUR_COUNT * PALETTE_COUNT))
		{
			destination[index / PALETTE_COLOUR_COUNT][index % PALETTE_COLOUR_COUNT] = Colour(source.readUshort(index * 2));
		}
	}

	void setupDrawing(OpenGL opengl)
	{
		renderer = new CarRenderer(this, opengl);
	}

	void draw(Camera camera, char[] keys)
	{
		renderer.draw(camera, keys);
	}
}
