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

		ubyte[] binaryData;
		ubyte[] binaryTextures;
		ubyte[] binaryPalettes1;
		ubyte[] binaryPalettes2;
		ubyte[] binaryPalettes3;

		float unknown1 = 0.5;
		float carCameraYOffset = 0.6;
		// Both these are Z X Y in the binaries
		// but the vec3fs are kept X Y Z
		// Wheels are in order: front L, front R, rear L, rear R
		vec3f[4] wheelOrigins;
		vec3f[4] lightOrigins;
		// Car 4 has an 0xA0 entry for all 0x29 model sections because they all have data
		uint[0x29] modelToTextureMap;
		// if a modelsection is empty (i.e. the roof ornament, it has an "empty" texture descriptor that uses no space)
		// the 30th modelsection (model[1]section[0] has the size 8 texture always)
		ubyte[][] textures;
		Colour[][] fixedPalettes;
		Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET][3] palettes;
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

	private void generateBinaries()
	{
		import std.zlib:compress;

		enum FIXED_DATA_END = 0x398;
		binaryData = [0,0,3,0x94,0,0,0,0];
		binaryData ~= nativeToBigEndian(unknown1);
		binaryData ~= nativeToBigEndian(carCameraYOffset);
		binaryData ~= [0,0,0,0];

		foreach(wheel; wheelOrigins)
		{
			binaryData ~= nativeToBigEndian(wheel.z);
			binaryData ~= nativeToBigEndian(wheel.x);
			binaryData ~= nativeToBigEndian(wheel.y);
		}
		foreach(light; lightOrigins)
		{
			binaryData ~= nativeToBigEndian(light.z);
			binaryData ~= nativeToBigEndian(light.x);
			binaryData ~= nativeToBigEndian(light.y);
		}
		binaryData ~= [0,0,0,0,0,0,0,0];

		// Until/if I handle the fixed palettes the inserted can just go in order
		uint palettePointer = FIXED_DATA_END;
		foreach(i; 0..8)
		{
			binaryData ~= nativeToBigEndian(palettePointer + (i * 0x20));
		}
		binaryData ~= [0,0,0,0];

		uint paletteSize = PALETTES_PER_SET * COLOURS_PER_PALETTE * 2;
		uint texturesSize = getTexturesSize();
		uint textureDescriptorsSize = textures.length * 0x20;
		
		uint a0Start = FIXED_DATA_END + paletteSize + texturesSize + textureDescriptorsSize;
		uint a0Count = modelToTextureMap.length;// + 4; // +4 moving wheel textures
		// 0xA0
		binaryData ~= nativeToBigEndian(a0Start);
		binaryData ~= [0,0,0,0];
		binaryData ~= nativeToBigEndian(a0Count);
		// After the 3rd LoD there is the weird small texture, then the four moving wheel textures
		// for now lets leave out the small mutant and see what happens
		binaryData ~= [0,0,0,0,0,0,0,0];

		uint b4Start = a0Start + ((modelToTextureMap.length) * 4);
		// 0xB4
		binaryData ~= nativeToBigEndian(b4Start);
		binaryData ~= [0,0,0,0xFF & textures.length];
		binaryData ~= [0,0,0,0,0,0,0,0,0,0,0,0];

		uint c8Start = b4Start + (textures.length * 4) + (4 * 0x20);
		// 0xC8
		binaryData ~= nativeToBigEndian(c8Start);
		binaryData ~= [0,0,0,0];
		binaryData ~= [0,0,0,4]; // moving wheel textures
		binaryData ~= [0,0,0,0,0,0,0,0];

		uint dcStart = c8Start + (4 * 4);
		// 0xDC
		binaryData ~= nativeToBigEndian(dcStart);
		binaryData ~= [0,0,0,4];
		binaryData ~= [0,0,0,0,	0,0,0,0];
		binaryData ~= nativeToBigEndian(a0Count);
		binaryData ~= [0,0,0,4];

		// 0xF4
		binaryData ~= new ubyte[0x2A4];
		binaryData ~= new ubyte[paletteSize];
		binaryData ~= new ubyte[texturesSize];

		if (binaryData.length % 8 != 0) // pad to next doubleword
		{
			binaryData ~= new ubyte[8 - binaryData.length % 8];
		}
		
		uint[] textureDescriptorPointers = new uint[textures.length];
		uint insertedTexturePointer = FIXED_DATA_END + paletteSize;
		// Body texture descriptors
		foreach (i, texture; textures)
		{
			textureDescriptorPointers[i] = binaryData.length;
			binaryData ~= [0xFD, 0x10, 0, 0];
			binaryData ~= nativeToBigEndian(insertedTexturePointer);
			binaryData ~= [0xE6, 0, 0, 0, 0, 0, 0, 0];
			if (texture.length > 8)
			{
				assert(texture.length == (80 * 38) / 2, "Texture is not 80*38");
				binaryData ~= [0xF3, 0, 0, 0, 7, 0x2F, 0x70, 0];
				insertedTexturePointer += texture.length;
			}
			else
			{
				assert(texture.length == 8, "Texture is not 8");
				binaryData ~= [0xF3, 0, 0, 0, 7, 0, 0x30, 0];
				insertedTexturePointer += i == 21 ? 8 : 0;
			}
			
			binaryData ~= [0xDF, 0, 0, 0, 0, 0, 0, 0];
		}
		
		foreach (modelNum, textureNum; modelToTextureMap)
		{
			binaryData ~= nativeToBigEndian(textureDescriptorPointers[textureNum]);
		}
		//binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 4]);
		//binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 3]);
		//binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 2]);
		//binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 1]);

		foreach (texturePointer; textureDescriptorPointers)
		{
			binaryData ~= nativeToBigEndian(texturePointer);
		}

		if (binaryData.length % 8 != 0) // pad to next doubleword
		{
			binaryData ~= new ubyte[8 - binaryData.length % 8];
		}
		// Moving wheel textures:
		insertedTexturePointer = FIXED_DATA_END + paletteSize + (((80 * 38) / 2) * (textures.length - 4));
		foreach (i, texture; textures[$-4..$])
		{
			textureDescriptorPointers[i] = binaryData.length;
			binaryData ~= [0xFD, 0x10, 0, 0];
			binaryData ~= nativeToBigEndian(insertedTexturePointer);
			binaryData ~= [0xE6, 0, 0, 0, 0, 0, 0, 0];
			assert(texture.length == (80 * 38) / 2, "Texture is not 80*38");
			binaryData ~= [0xF3, 0, 0, 0, 7, 0x2F, 0x70, 0];
			binaryData ~= [0xDF, 0, 0, 0, 0, 0, 0, 0];

			insertedTexturePointer += texture.length;
		}
		foreach (texturePointer; textureDescriptorPointers[0..4])
		{
			binaryData ~= nativeToBigEndian(texturePointer);
		}
		foreach (texturePointer; textureDescriptorPointers[0..4])
		{
			binaryData ~= nativeToBigEndian(texturePointer);
		}

		uint verticesPointer, normalsPointer, polygonsPointer;
		uint sectionIndex = 0;

		models[2].modelSections.length = 4;
		models[3].modelSections.length = 4;
		foreach (m, model; models)
		{
			verticesPointer = binaryData.length;
			foreach (vertex; model.vertices)
			{
				binaryData ~= nativeToBigEndian(vertex.z);
				binaryData ~= nativeToBigEndian(vertex.x);
				binaryData ~= nativeToBigEndian(vertex.y);
			}
			normalsPointer = binaryData.length;
			if (m == 0)
			{
				foreach (normal; model.normals)
				{
					binaryData ~= [normal.z, normal.x, normal.y]; // OK not to cast?
				}
			}

			if (binaryData.length % 16 != 0) // pad to next doubleword
			{
				binaryData ~= new ubyte[16 - binaryData.length % 16];
			}

			foreach (s, section; model.modelSections)
			{
				polygonsPointer = binaryData.length;
				foreach (polygon; section.polygons)
				{
					binaryData ~= [0,0,0,m == 0 ? 0x21 : 0];
					binaryData ~= [m == 0 ? cast(ubyte)s : 0x12,0,0,0];
					binaryData ~= nativeToBigEndian(polygon.vertexIndices[0]);
					binaryData ~= nativeToBigEndian(polygon.vertexIndices[1]);
					binaryData ~= nativeToBigEndian(polygon.vertexIndices[2]);
					binaryData ~= nativeToBigEndian(polygon.vertexIndices[3]);
					binaryData ~= polygon.textureCoordinates[0].u;
					binaryData ~= polygon.textureCoordinates[0].v;
					binaryData ~= polygon.textureCoordinates[1].u;
					binaryData ~= polygon.textureCoordinates[1].v;
					binaryData ~= polygon.textureCoordinates[2].u;
					binaryData ~= polygon.textureCoordinates[2].v;
					binaryData ~= polygon.textureCoordinates[3].u;
					binaryData ~= polygon.textureCoordinates[3].v;
					binaryData ~= nativeToBigEndian(polygon.normalIndices[0]);
					binaryData ~= nativeToBigEndian(polygon.normalIndices[1]);
					binaryData ~= nativeToBigEndian(polygon.normalIndices[2]);
					binaryData ~= nativeToBigEndian(polygon.normalIndices[3]);
				}
				
				foreach (nothing; 0..(m == 1 ? 4 : 1))
				{
					binaryData[(0xF4 + (sectionIndex * 0x10))..(0xF8 + (sectionIndex * 0x10))] = nativeToBigEndian(binaryData.length);
					sectionIndex++;
				}

				binaryData ~= nativeToBigEndian(verticesPointer);
				binaryData ~= nativeToBigEndian(model.vertices.length);
				binaryData ~= nativeToBigEndian(polygonsPointer);
				binaryData ~= nativeToBigEndian(section.polygons.length);
				binaryData ~= [0,0,0,0, 0,0,0,0]; // Not used right?
				binaryData ~= [0,0,0,0, 0,0,0,0]; // Not used right?
				binaryData ~= nativeToBigEndian(normalsPointer);
				binaryData ~= nativeToBigEndian(model.normals.length);
				binaryData ~= [0,0,0,0, 0,0,0,0]; // padding
			}
			
		}

		std.file.write("myBinaryData", binaryData);
		uint offset = 0;
		uint adder = 0x3E80;
		ubyte[] outfile = [0,0,0,0];
		outfile ~= nativeToBigEndian(binaryData.length);
		while (offset < binaryData.length)
		{
			if (offset + adder > binaryData.length)
			{
				adder = binaryData.length - offset;
			}
			//std.file.write(format("myBinaryDeflated %d", offset), compress(binaryData[offset..offset + adder]));
			outfile ~= nativeToBigEndian(compress(binaryData[offset..offset + adder]).length);
			outfile ~= compress(binaryData[offset..offset + adder]);
			if (outfile.length % 2 == 1 && offset + adder != binaryData.length)
			{
				outfile ~= [0];
			}
			offset += 0x3E80;
		}
		outfile[0..4] = nativeToBigEndian(outfile.length);
		std.file.write("myBinaryDataZlibBlock", outfile);
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
