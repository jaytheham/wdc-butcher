module wdc.car;

import std.file,		std.bitmanip,		std.algorithm,
	   camera,
	   gfm.math,		gfm.opengl,
	   wdc.tools,		wdc.drawable,		wdc.renderer,
       wdc.carRenderer;
// Hold all information about a Car asset (and the ability to convert it to N64 binaries)
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
		enum TEXTURE_WIDTH_BYTES = 40;
		enum TEXTURE_HEIGHT_BYTES = 38;
		enum TEXTURE_SIZE_BYTES = TEXTURE_WIDTH_BYTES * TEXTURE_HEIGHT_BYTES;
		const static string OBJ_WHEEL_ID = "wheel_origins";
		const static string OBJ_LIGHT_ID = "light_origins";
		const static ubyte[] MODEL_TO_PALETTE = [0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,1,
		                                         0,1,2,4,4,6,6,1,1,0,3,3,3,2,2,2,
		                                         2,2,2,2,2,2,2,2,2,2,2];
		enum PartNames {
			grill,         bonnet_l,      bonnet_r,      windscreen_f,  roof,
			windscreen_b,  trunk,         back,          wheel_well_fl, wheel_well_fr,
			wheel_well_bl, wheel_well_br, door_l,        door_r,        windows_l,
			windows_r,     spoiler,       undercarriage, fake_wheels,   headlight_l,
			headlight_r,   taillight_l,   taillight_r,   wingmirror_l,  wingmirror_r,
			roof_ornament, LoD1,          LoD2,          LoD3};
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
		uint[] modelToTextureMap;
		// if a modelsection is empty (i.e. the roof ornament, it has an "empty" texture descriptor that uses no space)
		// sometimes they have a size of 8, often model[1]section[0] does
		ubyte[][] textures;
		Colour[][] fixedPalettes;
		Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET][3] paletteSets;
		int[PALETTES_PER_SET] insertedPaletteIndices;
		Model[10] models;
	
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
			vec3s[] vertices;
			vec3b[] normals;
			ModelSection[] modelSections;
		}

		struct ModelSection
		{
			Polygon[] polygons;
		}

		struct Polygon
		{
			ushort[4] vertexIndices;
			vec2b[4] textureCoordinates;
			ushort[4] normalIndices;
		}
	}

	private void removeRepeatedVertices()
	{
		foreach (ref model; models)
		{
			int[] newIndices = new int[model.vertices.length];
			int[] removals;
			bool found;
			foreach (current, currentVertex; model.vertices)
			{
				found = false;
				foreach (p, previousVertex; model.vertices[0..current])
				{
					if (currentVertex == previousVertex)
					{
						newIndices[current] = newIndices[p];
						removals ~= current;
						found = true;
						break;
					}
				}
				if (!found)
				{
					newIndices[current] = current - removals.length;
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
		removeRepeatedVertices();

		enum FIXED_DATA_END = 0x398;
		modelsBinary = [0,0,3,0x94, 0,0,0,0];
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
		modelsBinary ~= [0,0,0,0, 0,0,0,0];

		// Until/if I handle the fixed palettes the inserted can just go in order
		foreach(i; 0..8)
		{
			modelsBinary ~= nativeToBigEndian(FIXED_DATA_END + (i * 0x20));
		}
		modelsBinary ~= [0,0,0,0];

		uint paletteSize = PALETTES_PER_SET * COLOURS_PER_PALETTE * 2;
		uint texturesSize = getTexturesSize();
		uint textureDescriptorsSize = textures.length * 0x20;
		
		uint a0Start = FIXED_DATA_END + paletteSize + texturesSize + textureDescriptorsSize;
		uint a0Count = modelToTextureMap.length;
		modelsBinary ~= nativeToBigEndian(a0Start);
		modelsBinary ~= [0,0,0,0];
		modelsBinary ~= nativeToBigEndian(a0Count);
		modelsBinary ~= [0,0,0,0, 0,0,0,0];

		uint b4Start = a0Start + ((modelToTextureMap.length) * 4);
		modelsBinary ~= nativeToBigEndian(b4Start);
		modelsBinary ~= [0,0,0,0xFF & textures.length];
		modelsBinary ~= [0,0,0,0, 0,0,0,0, 0,0,0,0];

		uint dcStart = pad(b4Start + (textures.length * 4) + (4 * 0x20), 8);
		uint c8Start = dcStart + (4 * 4);
		modelsBinary ~= nativeToBigEndian(c8Start);
		modelsBinary ~= [0,0,0,0];
		modelsBinary ~= [0,0,0,4];
		modelsBinary ~= [0,0,0,0, 0,0,0,0];

		modelsBinary ~= nativeToBigEndian(dcStart);
		modelsBinary ~= [0,0,0,4];
		modelsBinary ~= [0,0,0,0, 0,0,0,0];

		modelsBinary ~= nativeToBigEndian(a0Count);
		modelsBinary ~= [0,0,0,4];

		// 0xF4
		modelsBinary ~= new ubyte[0x2A4 + paletteSize + texturesSize];

		pad(modelsBinary, 8);
		
		uint[] textureDescriptorPointers = new uint[textures.length];
		uint texelsPointer = FIXED_DATA_END + paletteSize;
		foreach (i, texture; textures)
		{
			textureDescriptorPointers[i] = modelsBinary.length;
			modelsBinary ~= [0xFD, 0x10, 0, 0];
			modelsBinary ~= nativeToBigEndian(texelsPointer);
			modelsBinary ~= [0xE6, 0, 0, 0, 0, 0, 0, 0];
			if (texture.length == (80 * 38) / 2)
			{
				modelsBinary ~= [0xF3,0,0,0, 7, 0x2F, 0x70, 0];
			}
			else
			{
				assert(texture.length == 8, "Texture is neither 4x4 nor 80x38");
				modelsBinary ~= [0xF3,0,0,0, 7, 0, 0x30, 0];
			}
			modelsBinary ~= [0xDF,0,0,0, 0,0,0,0];
			texelsPointer += texture.length;
			ubyte[] rowSwappedTexture = texture.dup;
			if (rowSwappedTexture.length == (40 * 38))
			{
				wordSwapOddRows(rowSwappedTexture, 40, 38);
			}
			texturesBinary ~= rowSwappedTexture;
		}
		
		foreach (modelNum, textureNum; modelToTextureMap)
		{
			modelsBinary ~= nativeToBigEndian(textureDescriptorPointers[textureNum]);
		}

		foreach (pointer; textureDescriptorPointers)
		{
			modelsBinary ~= nativeToBigEndian(pointer);
		}

		pad(modelsBinary, 8);

		// Moving wheel textures:
		uint descriptorPointer;
		foreach (i, texture; textures[$-4..$])
		{
			descriptorPointer = modelsBinary.length;
			modelsBinary ~= modelsBinary[textureDescriptorPointers[(textures.length - 4) + i]
			                             ..
			                             textureDescriptorPointers[(textures.length - 4) + i] + 0x20];
			textureDescriptorPointers[(textures.length - 4) + i] = descriptorPointer;
		}
		foreach (texturePointer; textureDescriptorPointers[$-4..$])
		{
			modelsBinary ~= nativeToBigEndian(texturePointer);
		}
		foreach (texturePointer; textureDescriptorPointers[$-4..$])
		{
			modelsBinary ~= nativeToBigEndian(texturePointer);
		}

		uint sectionIndex = 0;
		uint verticesPointer, normalsPointer, polygonsPointer, unkPointer;

		foreach (model; models[2..$])
		{
			model.modelSections.length = 1;// Even though they're almost certainly empty!
		}

		foreach (modelIndex, model; models)
		{
			verticesPointer = modelsBinary.length;
			foreach (vertex; model.vertices)
			{
				modelsBinary ~= nativeToBigEndian(vertex.z);
				modelsBinary ~= nativeToBigEndian(vertex.x);
				modelsBinary ~= nativeToBigEndian(vertex.y);
			}
			if (modelIndex == 0)
			{
				modelsBinary ~= [0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0];
			}

			pad(modelsBinary, 8);

			if (modelIndex == 0)
			{
				normalsPointer = modelsBinary.length;
				foreach (normal; model.normals)
				{
					modelsBinary ~= [normal.z, normal.x, normal.y];
				}
			}

			pad(modelsBinary, 8);

			unkPointer = modelsBinary.length;
			if (modelIndex == 1)
			{
				modelsBinary ~= [0,0,0,0xFF];
			}

			pad(modelsBinary, 16);

			foreach (s, section; model.modelSections)
			{
				polygonsPointer = modelsBinary.length;
				foreach (polygon; section.polygons)
				{
					modelsBinary ~= [0,0,0,modelIndex == 0 ? 0x21 : 0];
					modelsBinary ~= [modelIndex == 0 ? cast(ubyte)s : 0x12,0,0,0];
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[0]);
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[1]);
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[2]);
					modelsBinary ~= nativeToBigEndian(polygon.vertexIndices[3]);
					modelsBinary ~= polygon.textureCoordinates[0].x;
					modelsBinary ~= polygon.textureCoordinates[0].y;
					modelsBinary ~= polygon.textureCoordinates[1].x;
					modelsBinary ~= polygon.textureCoordinates[1].y;
					modelsBinary ~= polygon.textureCoordinates[2].x;
					modelsBinary ~= polygon.textureCoordinates[2].y;
					modelsBinary ~= polygon.textureCoordinates[3].x;
					modelsBinary ~= polygon.textureCoordinates[3].y;
					modelsBinary ~= nativeToBigEndian(modelIndex == 0 ? polygon.normalIndices[0] : cast(ushort)0);
					modelsBinary ~= nativeToBigEndian(modelIndex == 0 ? polygon.normalIndices[1] : cast(ushort)0);
					modelsBinary ~= nativeToBigEndian(modelIndex == 0 ? polygon.normalIndices[2] : cast(ushort)0);
					modelsBinary ~= nativeToBigEndian(modelIndex == 0 ? polygon.normalIndices[3] : cast(ushort)0);
				}
				
				foreach (nothing; 0..(modelIndex == 1 ? 4 : 1))
				{
					modelsBinary[(0xF4 + (sectionIndex * 0x10))..(0xF8 + (sectionIndex * 0x10))] = nativeToBigEndian(modelsBinary.length);
					sectionIndex++;
				}

				modelsBinary ~= nativeToBigEndian(verticesPointer);
				modelsBinary ~= nativeToBigEndian(model.vertices.length + 5);
				modelsBinary ~= nativeToBigEndian(polygonsPointer);
				modelsBinary ~= nativeToBigEndian(section.polygons.length);
				if (modelIndex == 1)
				{
					modelsBinary ~= nativeToBigEndian(unkPointer);
					modelsBinary ~= [0,0,0,0];
					modelsBinary ~= nativeToBigEndian(unkPointer);
					modelsBinary ~= [0,0,0,1];
				}
				else
				{
					modelsBinary ~= nativeToBigEndian(unkPointer);
					modelsBinary ~= [0,0,0,0];
					modelsBinary ~= [0,0,0,0, 0,0,0,0];
				}
				
				if (modelIndex == 0)
				{
					modelsBinary ~= nativeToBigEndian(normalsPointer);
					modelsBinary ~= nativeToBigEndian(model.normals.length);
				}
				else
				{
					modelsBinary ~= [0,0,0,0, 0,0,0,0];
				}
				modelsBinary ~= [0,0,0,0, 0,0,0,0];
			}
		}

		generatePaletteBinaries();

		//std.file.write("mymodelsBinary", modelsBinary);
		//std.file.write("myTexturesBinary", texturesBinary);
		modelsZlib = binaryToZlibBlock(modelsBinary);
		texturesZlib = binaryToZlibBlock(texturesBinary);
		//std.file.write("mymodelsBinaryZlibBlock", modelsZlib);
		//std.file.write("myTexturesBinaryZlibBlock", texturesZlib);
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
		import std.zlib : compress;
		uint position = 0;
		uint chunkSize = 0x3E80;
		ubyte[] buffer;
		ubyte[] zlibBlock = [0,0,0,0];

		zlibBlock ~= nativeToBigEndian(data.length);
		while (position < data.length)
		{
			if (position + chunkSize > data.length)
			{
				chunkSize = data.length - position;
			}
			buffer = compress(data[position..position + chunkSize], 9);
			zlibBlock ~= nativeToBigEndian(buffer.length);
			zlibBlock ~= buffer;
			if (zlibBlock.length % 2 == 1)
			{
				zlibBlock ~= [0];
			}
			position += chunkSize;
		}
		zlibBlock[0..4] = nativeToBigEndian(zlibBlock.length);
		return zlibBlock;
	}

	private void pad(ref ubyte[] target, uint size)
	{
		if (target.length % size != 0)
		{
			target ~= new ubyte[size - (target.length % size)];
		}
	}

	private uint pad(uint value, uint boundary)
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
