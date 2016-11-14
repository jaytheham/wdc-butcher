module wdc.car;

import std.file,		std.bitmanip,		std.algorithm,
	   camera,
	   gfm.math,		gfm.opengl,
	   wdc.tools,		wdc.drawable,		wdc.renderer,
       wdc.carRenderer;
// Hold all information about a Car asset (and the ability to convert it to N64 binaries)
union Colour
{
	ushort whole;
	mixin(bitfields!(
		ubyte, "alpha",		1,
		ubyte,	"b",		5,
		ubyte,	"g",		5,
		ubyte,	"r",		5));
}

class Car : Drawable
{
	private
	{
		CarRenderer renderer;
	}
	public
	{
		enum COLOURS_PER_PALETTE = 0x10;
		enum PALETTES_PER_SET = 8;
		const static string OBJ_WHEEL_ID = "wheel_origins";
		const static string OBJ_LIGHT_ID = "light_origins";
		const static ubyte[] MODEL_TO_PALETTE = [0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,1,
		                                         0,1,2,4,5,6,7,1,1,1,3,3,3,3,2,2,
		                                         2,2,2,2,2,2,2,2,2,2,2];
		                                         // cheat by saying second light of each pair uses lit palette
		const static string[] partNames = [
			"grill",		"bonnet_l",		"bonnet_r",		"windscreen_f",		"roof",			"windscreen_b",
			"trunk",		"back",			"wheel_well_fl","wheel_well_fr",	"wheel_well_bl","wheel_well_br",
			"door_l",		"door_r",		"windows_l",	"windows_r",		"spoiler",		"undercarriage",
			"fake_wheels",	"headlight_l",	"headlight_r",	"taillight_l",		"taillight_r",	"wingmirror_l",
			"wingmirror_r", "roof_ornament","LoD1",			"LoD2",				"LoD3"];
		// cars 23, 24, 25, 26, 27, 30, 31, 32 have a roof ornament
		// cars 9, 10, 11, 20, 21, 22 have fake wheels
		// 30, 31, 32 have no under carriage

		ubyte[] modelsBinary;
		ubyte[] modelsZlib;
		ubyte[] texturesBinary;
		ubyte[] texturesZlib;
		ubyte[][3] paletteBinaries;

		float unknown1 = 0.5;
		float carCameraYOffset = 0.6;
		// Both these are Z X Y in the binaries
		// but the vec3fs are kept X Y Z
		// Wheels are in order: front L, front R, rear L, rear R
		vec3f[4] wheelOrigins;
		vec3f[4] lightOrigins;
		// Car 4 has an 0xA0 entry for all 0x29 model sections because they all have data
		// this must be variable in size, but also correct (?) (car 0 must be 0x22)
		uint[0x22] modelToTextureMap;
		// if a modelsection is empty (i.e. the roof ornament, it has an "empty" texture descriptor that uses no space)
		// sometimes they have a size of 8, often model[1]section[0] does
		ubyte[][] textures;
		Colour[][] fixedPalettes;
		Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET][3] paletteSets;
		int[PALETTES_PER_SET] insertedPaletteIndices;
		Model[10] models;
	
		

		struct Model
		{
			Vertex[] vertices;
			Normal[] normals;
			ModelSection[] modelSections;
		}

		struct Vertex
		{
			short z;
			short x;
			short y;
		}

		struct Normal
		{
			byte z;
			byte x;
			byte y;
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
			byte u;
			byte v;
		}
	}

	this(){}

	private void removeRepeatedVertices()
	{
		foreach (ref model; models)
		{
			int[] newIndices = new int[model.vertices.length];
			int[] removals;
			bool found = false;
			foreach (c, currentVertex; model.vertices)
			{
				found = false;
				foreach (p, previousVertex; model.vertices[0..c])
				{
					if (currentVertex == previousVertex)
					{
						newIndices[c] = newIndices[p];
						removals ~= c;
						found = true;
						break;
					}
				}
				if (!found)
				{
					newIndices[c] = c - removals.length;
				}
			}

			// remove
			foreach_reverse (i, value; removals)
			{
				model.vertices = remove(model.vertices, value);
			}
			
			foreach (ref section; model.modelSections)
			{
				foreach (ref polygon; section.polygons)
				{
					foreach (ref vertexIndex; polygon.vertexIndices)
					{
						if (vertexIndex == 0xFFFF)
						{
							continue;
						}
						vertexIndex = cast(ushort)newIndices[vertexIndex];
					}
				}
			}
		}
	}

	public void generateBinaries()
	{
		enum FIXED_DATA_END = 0x398;
		modelsBinary = [0,0,3,0x94,0,0,0,0];
		modelsBinary ~= nativeToBigEndian(unknown1);
		modelsBinary ~= nativeToBigEndian(carCameraYOffset);
		modelsBinary ~= [0,0,0,0];

		foreach(wheel; wheelOrigins)
		{
			modelsBinary ~= nativeToBigEndian(wheel.z);
			modelsBinary ~= nativeToBigEndian(wheel.x);
			modelsBinary ~= nativeToBigEndian(wheel.y);
		}
		foreach(light; lightOrigins)
		{
			modelsBinary ~= nativeToBigEndian(light.z);
			modelsBinary ~= nativeToBigEndian(light.x);
			modelsBinary ~= nativeToBigEndian(light.y);
		}
		modelsBinary ~= [0,0,0,0,0,0,0,0];

		// Until/if I handle the fixed palettes the inserted can just go in order
		uint palettePointer = FIXED_DATA_END;
		foreach(i; 0..8)
		{
			modelsBinary ~= nativeToBigEndian(palettePointer + (i * 0x20));
		}
		modelsBinary ~= [0,0,0,0];

		uint paletteSize = PALETTES_PER_SET * COLOURS_PER_PALETTE * 2;
		uint texturesSize = getTexturesSize();
		uint textureDescriptorsSize = textures.length * 0x20;
		
		uint a0Start = FIXED_DATA_END + paletteSize + texturesSize + textureDescriptorsSize;
		uint a0Count = modelToTextureMap.length;// + 4; // +4 moving wheel textures
		// 0xA0
		modelsBinary ~= nativeToBigEndian(a0Start);
		modelsBinary ~= [0,0,0,0];
		modelsBinary ~= nativeToBigEndian(a0Count);
		// After the 3rd LoD there is the weird small texture, then the four moving wheel textures
		// for now lets leave out the small mutant and see what happens
		modelsBinary ~= [0,0,0,0,0,0,0,0];

		uint b4Start = a0Start + ((modelToTextureMap.length) * 4);
		// 0xB4
		modelsBinary ~= nativeToBigEndian(b4Start);
		modelsBinary ~= [0,0,0,0xFF & textures.length];
		modelsBinary ~= [0,0,0,0,0,0,0,0,0,0,0,0];

		uint dcStart = padToXBytes(b4Start + (textures.length * 4) + (4 * 0x20), 8);
		uint c8Start = dcStart + (4 * 4);
		// 0xC8
		modelsBinary ~= nativeToBigEndian(c8Start);
		modelsBinary ~= [0,0,0,0];
		modelsBinary ~= [0,0,0,4]; // moving wheel textures
		modelsBinary ~= [0,0,0,0,0,0,0,0];

		
		// 0xDC
		modelsBinary ~= nativeToBigEndian(dcStart);
		modelsBinary ~= [0,0,0,4];
		modelsBinary ~= [0,0,0,0,	0,0,0,0];
		modelsBinary ~= nativeToBigEndian(a0Count);
		modelsBinary ~= [0,0,0,4];

		// 0xF4
		modelsBinary ~= new ubyte[0x2A4];
		modelsBinary ~= new ubyte[paletteSize];
		modelsBinary ~= new ubyte[texturesSize];

		if (modelsBinary.length % 8 != 0) // pad to next doubleword
		{
			modelsBinary ~= new ubyte[8 - modelsBinary.length % 8];
		}
		
		uint[] textureDescriptorPointers = new uint[textures.length];
		uint insertedTexturePointer = FIXED_DATA_END + paletteSize;
		// Body texture descriptors
		foreach (i, texture; textures)
		{
			textureDescriptorPointers[i] = modelsBinary.length;
			modelsBinary ~= [0xFD, 0x10, 0, 0];
			modelsBinary ~= nativeToBigEndian(insertedTexturePointer);
			modelsBinary ~= [0xE6, 0, 0, 0, 0, 0, 0, 0];
			if (texture.length == (80 * 38) / 2)
			{
				modelsBinary ~= [0xF3, 0, 0, 0, 7, 0x2F, 0x70, 0];
				insertedTexturePointer += texture.length;
			}
			else
			{
				//assert(texture.length == 8, "Texture is not 8");
				modelsBinary ~= [0xF3, 0, 0, 0, 7, 0, 0x30, 0];
				insertedTexturePointer += texture.length;
			}
			texturesBinary ~= texture;
			
			modelsBinary ~= [0xDF, 0, 0, 0, 0, 0, 0, 0];
		}
		
		foreach (modelNum, textureNum; modelToTextureMap)
		{
			modelsBinary ~= nativeToBigEndian(textureDescriptorPointers[textureNum]);
		}
		//modelsBinary ~= nativeToBigEndian(textureDescriptorPointers[$ - 4]);
		//modelsBinary ~= nativeToBigEndian(textureDescriptorPointers[$ - 3]);
		//modelsBinary ~= nativeToBigEndian(textureDescriptorPointers[$ - 2]);
		//modelsBinary ~= nativeToBigEndian(textureDescriptorPointers[$ - 1]);

		foreach (texturePointer; textureDescriptorPointers)
		{
			modelsBinary ~= nativeToBigEndian(texturePointer);
		}

		if (modelsBinary.length % 8 != 0) // pad to next doubleword
		{
			modelsBinary ~= new ubyte[8 - modelsBinary.length % 8];
		}
		// Moving wheel textures:

		uint temp;
		foreach (i, texture; textures[$-4..$])
		{
			//textureDescriptorPointers[i] = modelsBinary.length;
			//modelsBinary ~= [0xFD, 0x10, 0, 0];
			//modelsBinary ~= nativeToBigEndian(insertedTexturePointer);
			//modelsBinary ~= [0xE6, 0, 0, 0, 0, 0, 0, 0];
			//assert(texture.length == (80 * 38) / 2, "Texture is not 80*38");
			//modelsBinary ~= [0xF3, 0, 0, 0, 7, 0x2F, 0x70, 0];
			//modelsBinary ~= [0xDF, 0, 0, 0, 0, 0, 0, 0];

			//insertedTexturePointer += texture.length;
			temp = modelsBinary.length;
			modelsBinary ~= modelsBinary[textureDescriptorPointers[(textures.length - 4) + i]..textureDescriptorPointers[(textures.length - 4) + i] + 0x20];
			textureDescriptorPointers[(textures.length - 4) + i] = temp;
		}
		foreach (texturePointer; textureDescriptorPointers[$-4..$])
		{
			modelsBinary ~= nativeToBigEndian(texturePointer);
		}
		foreach (texturePointer; textureDescriptorPointers[$-4..$])
		{
			modelsBinary ~= nativeToBigEndian(texturePointer);
		}

		uint verticesPointer, normalsPointer, polygonsPointer, unkPointer;
		uint sectionIndex = 0;

		models[2].modelSections.length = 4;
		models[3].modelSections.length = 4;
		foreach (m, model; models)
		{
			verticesPointer = modelsBinary.length;
			foreach (vertex; model.vertices)
			{
				modelsBinary ~= nativeToBigEndian(vertex.z);
				modelsBinary ~= nativeToBigEndian(vertex.x);
				modelsBinary ~= nativeToBigEndian(vertex.y);
			}
			normalsPointer = modelsBinary.length;
			if (m == 0)
			{
				foreach (normal; model.normals)
				{
					modelsBinary ~= [normal.z, normal.x, normal.y]; // OK not to cast?
				}
			}

			if (m == 1)
			{
				unkPointer = modelsBinary.length;
				modelsBinary ~= [0,0,0,0xFF];
			}

			if (modelsBinary.length % 16 != 0) // pad to next doubleword
			{
				modelsBinary ~= new ubyte[16 - modelsBinary.length % 16];
			}

			foreach (s, section; model.modelSections)
			{
				polygonsPointer = modelsBinary.length;
				foreach (polygon; section.polygons)
				{
					modelsBinary ~= [0,0,0,m == 0 ? 0x21 : 0];
					modelsBinary ~= [m == 0 ? cast(ubyte)s : 0x12,0,0,0];
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[0]);
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[1]);
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[2]);
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[3]);
					modelsBinary ~= polygon.textureCoordinates[0].u;
					modelsBinary ~= polygon.textureCoordinates[0].v;
					modelsBinary ~= polygon.textureCoordinates[1].u;
					modelsBinary ~= polygon.textureCoordinates[1].v;
					modelsBinary ~= polygon.textureCoordinates[2].u;
					modelsBinary ~= polygon.textureCoordinates[2].v;
					modelsBinary ~= polygon.textureCoordinates[3].u;
					modelsBinary ~= polygon.textureCoordinates[3].v;
					modelsBinary ~= nativeToBigEndian(m == 0 ? polygon.normalIndices[0] : cast(ushort)0);
					modelsBinary ~= nativeToBigEndian(m == 0 ? polygon.normalIndices[1] : cast(ushort)0);
					modelsBinary ~= nativeToBigEndian(m == 0 ? polygon.normalIndices[2] : cast(ushort)0);
					modelsBinary ~= nativeToBigEndian(m == 0 ? polygon.normalIndices[3] : cast(ushort)0);
				}
				
				foreach (nothing; 0..(m == 1 ? 4 : 1))
				{
					modelsBinary[(0xF4 + (sectionIndex * 0x10))..(0xF8 + (sectionIndex * 0x10))] = nativeToBigEndian(modelsBinary.length);
					sectionIndex++;
				}

				modelsBinary ~= nativeToBigEndian(verticesPointer);
				modelsBinary ~= nativeToBigEndian(model.vertices.length);
				modelsBinary ~= nativeToBigEndian(polygonsPointer);
				modelsBinary ~= nativeToBigEndian(section.polygons.length);
				if (m == 1)
				{
					modelsBinary ~= nativeToBigEndian(unkPointer);
					modelsBinary ~= [0,0,0,0]; // Not used right?
					modelsBinary ~= nativeToBigEndian(unkPointer);
					modelsBinary ~= [0,0,0,1]; // Not used right?
				}
				else
				{
					modelsBinary ~= [0,0,0,0, 0,0,0,0]; // Not used right?
					modelsBinary ~= [0,0,0,0, 0,0,0,0]; // Not used right?
				}
				
				if (m == 0)
				{
					modelsBinary ~= nativeToBigEndian(normalsPointer);
					modelsBinary ~= nativeToBigEndian(model.normals.length);
				}
				else
				{
					modelsBinary ~= [0,0,0,0, 0,0,0,0];
				}
				modelsBinary ~= [0,0,0,0, 0,0,0,0]; // padding
			}
			
		}

		generatePaletteBinaries();

		std.file.write("mymodelsBinary", modelsBinary);
		std.file.write("myTexturesBinary", texturesBinary);
		modelsZlib = binaryToZlibBlock(modelsBinary);
		texturesZlib = binaryToZlibBlock(texturesBinary);
		std.file.write("mymodelsBinaryZlibBlock", modelsZlib);
		std.file.write("myTexturesBinaryZlibBlock", texturesZlib);
	}

	private void generatePaletteBinaries()
	{
		foreach (i, set; paletteSets)
		{
			foreach (palette; set)
			{
				foreach (colour; palette)
				{
					paletteBinaries[i] ~= nativeToBigEndian(colour.whole);
				}
			}
		}
	}

	private ubyte[] binaryToZlibBlock(ref ubyte[] data)
	{
		import std.zlib:compress;
		uint offset = 0;
		uint chunkSize = 0x3E80;
		ubyte[] buffer;
		ubyte[] outfile = [0,0,0,0];

		outfile ~= nativeToBigEndian(data.length);
		while (offset < data.length)
		{
			if (offset + chunkSize > data.length)
			{
				chunkSize = data.length - offset;
			}
			buffer = compress(data[offset..offset + chunkSize], 9);
			outfile ~= nativeToBigEndian(buffer.length);
			outfile ~= buffer;
			if (outfile.length % 2 == 1)
			{
				outfile ~= [0];
			}
			offset += chunkSize;
		}
		outfile[0..4] = nativeToBigEndian(outfile.length);
		return outfile;
	}

	private uint padToXBytes(uint value, uint boundary)
	{
		if (value % boundary != 0)
		{
			value += boundary - (value % boundary);
		}
		return value;
	}

	private uint getTexturesSize()
	{
		uint size = 0;
		foreach(texture; textures)
		{
			size += texture.length;
		}
		return size;
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
