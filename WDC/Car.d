module wdc.car;

import std.stdio,	   std.array,	   std.file,
	   std.format,	   std.bitmanip,   std.typecons,
	   std.algorithm,
	   camera,
	   gfm.math,	   gfm.opengl,
	   wdc.tools,	   wdc.drawable,   wdc.renderer,
	   wdc.png,        wdc.carRenderer;
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

		enum COLOURS_PER_PALETTE = 0x10;
		enum PALETTES_PER_SET = 8;
		enum OBJ_WHEEL_ID = "wheel_origins";
		enum OBJ_LIGHT_ID = "light_origins";
		ubyte[] MODEL_TO_PALETTE = [0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,1,
		                            0,1,2,4,5,6,7,1,1,1,3,3,3,3,2,2,
		                            2,2,2,2,2,2,2,2,2,2,2]; // cheat by saying second light of each pair uses lit palette

		const string[] partNames = ["grill", "bonnet_l", "bonnet_r", "windscreen_f", "roof", "windscreen_b", "trunk",
		                            "back", "wheel_well_fl", "wheel_well_fr", "wheel_well_bl", "wheel_well_br",
		                            "door_l", "door_r", "windows_l", "windows_r", "spoiler", "undercarriage", "part_x",
		                            "headlight_l", "headlight_r", "taillight_l", "taillight_r",
		                            "wingmirror_l", "wingmirror_r", "roof_ornament", "LoD1", "LoD2", "LoD3"];

		float unknown1 = 0.5;
		float carCameraYOffset = 0.6;
		// Both these are Z X Y in the binaries
		// but the vec3fs are kept X Y Z
		vec3f[4] wheelOrigins;
		vec3f[4] lightOrigins;
		uint[] modelToTextureMap;
		ubyte[][] bodyTextures;
		Colour[][] fixedPalettes;
		Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET] palettesA;
		Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET] palettesB;
		Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET] palettesC;
		int[PALETTES_PER_SET] insertedPaletteIndices;
		Model[] models;
	}
	public
	{
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

	this(ubyte[] dataBlob, ubyte[] textureSource, ubyte[] inPalettesA, ubyte[] inPalettesB, ubyte[] inPalettesC)
	{
		binaryData = dataBlob;
		binaryTextures = textureSource;
		binaryPalettes1 = inPalettesA;
		binaryPalettes2 = inPalettesB;
		binaryPalettes3 = inPalettesC;

		unknown1 = binaryData.readFloat(0x8);
		carCameraYOffset = binaryData.readFloat(0xC);
		wheelOrigins = [vec3f(binaryData.readFloat(0x18),binaryData.readFloat(0x1C),binaryData.readFloat(0x14)),
		                vec3f(binaryData.readFloat(0x24),binaryData.readFloat(0x28),binaryData.readFloat(0x20)),
		                vec3f(binaryData.readFloat(0x30),binaryData.readFloat(0x34),binaryData.readFloat(0x2C)),
		                vec3f(binaryData.readFloat(0x3C),binaryData.readFloat(0x40),binaryData.readFloat(0x38))];
		lightOrigins = [vec3f(binaryData.readFloat(0x48),binaryData.readFloat(0x4C),binaryData.readFloat(0x44)),
		                vec3f(binaryData.readFloat(0x54),binaryData.readFloat(0x58),binaryData.readFloat(0x50)),
		                vec3f(binaryData.readFloat(0x60),binaryData.readFloat(0x64),binaryData.readFloat(0x5C)),
		                vec3f(binaryData.readFloat(0x6C),binaryData.readFloat(0x70),binaryData.readFloat(0x68))];

		parseBinaryTextures();

		parseBinaryPalettes(inPalettesA, palettesA);
		parseBinaryPalettes(inPalettesB, palettesB);
		parseBinaryPalettes(inPalettesC, palettesC);

		parseBinaryFixedPalettes();

		parseBinaryModels();
	}

	this(string objFilePath)
	{
		import std.string, std.conv;
		
		int currentModel = 0xffff, currentModelSection,
		    totalVertexCount = 0, sectionVertexCount = 0,
		    normalOffset, sectionNormalCount,
		    uvOffset;
		string line;
		string[] lineParts, materialPaths;
		TextureCoordinate[] sectionUvs;
		string[][] faces;
		File input = File(objFilePath, "r");

		// TODO: this map should always be this size right? for import and export rather than added to
		modelToTextureMap = new uint[0x1E];

		void facesToPolygons()
		{
			string[] point1, point2, point3, point4;
			foreach (face; faces)
			{
				point1 = split(face[0], "/");
				point2 = split(face[1], "/");
				point3 = split(face[2], "/");
				point4 = face.length == 4 ? split(face[3], "/") : null;
				models[currentModel].modelSections[currentModelSection].polygons ~= Polygon(
					[
					cast(ushort)((parse!uint(point1[0]) - totalVertexCount - 1) + (models[currentModel].vertices.length - sectionVertexCount)),
					cast(ushort)((parse!uint(point2[0]) - totalVertexCount - 1) + (models[currentModel].vertices.length - sectionVertexCount)),
					cast(ushort)((parse!uint(point3[0]) - totalVertexCount - 1) + (models[currentModel].vertices.length - sectionVertexCount)),
					point4 != null ? cast(ushort)((parse!uint(point4[0]) - totalVertexCount - 1) + (models[currentModel].vertices.length - sectionVertexCount)) : cast(ushort)0xFFFF
					],
					[
					sectionUvs[parse!uint(point1[1]) - uvOffset - 1],
					sectionUvs[parse!uint(point2[1]) - uvOffset - 1],
					sectionUvs[parse!uint(point3[1]) - uvOffset - 1],
					point4 != null ? sectionUvs[parse!uint(point4[1]) - uvOffset - 1] : TextureCoordinate(0,0)
					],
					[
					cast(ushort)((parse!uint(point1[2]) - normalOffset - 1) + (models[currentModel].normals.length - sectionNormalCount)),
					cast(ushort)((parse!uint(point2[2]) - normalOffset - 1) + (models[currentModel].normals.length - sectionNormalCount)),
					cast(ushort)((parse!uint(point3[2]) - normalOffset - 1) + (models[currentModel].normals.length - sectionNormalCount)),
					point4 != null ? cast(ushort)((parse!uint(point4[2]) - normalOffset - 1) + (models[currentModel].normals.length - sectionNormalCount)) : 0
					]
					);
			}
		}

		while((line = input.readln()) !is null)
		{
			line = chomp(line);
			
			if (line.startsWith("o "))
			{
				if (currentModel != 0xffff)
					{
						facesToPolygons();
					}
				lineParts = split(line[2..$], "-");
				if (lineParts[0] == OBJ_WHEEL_ID)
				{
					// TODO assert there are four verts here
					currentModel = 0xffff;
					foreach (i; 0..4)
					{
						line = input.readln();
						lineParts = split(line[2..$], " ");
						wheelOrigins[i] = vec3f(parse!float(lineParts[0]), parse!float(lineParts[1]), parse!float(lineParts[2]));
					}
					totalVertexCount += 4;
				}
				else if (lineParts[0] == OBJ_LIGHT_ID)
				{
					// TODO assert there are four verts here
					currentModel = 0xffff;
					foreach (i; 0..4)
					{
						line = input.readln();
						lineParts = split(line[2..$], " ");
						lightOrigins[i] = vec3f(parse!float(lineParts[0]), parse!float(lineParts[1]), parse!float(lineParts[2]));
					}
					totalVertexCount += 4;
				}
				else if (lineParts.length >= 2)
				{
					// new section
					currentModel = parse!int(lineParts[0]);
					currentModelSection = parse!int(lineParts[1]);
					while (models.length <= currentModel)
					{
						models ~= Model();
					}
					while (models[currentModel].modelSections.length <= currentModelSection)
					{
						models[currentModel].modelSections ~= ModelSection();
					}
					totalVertexCount += sectionVertexCount;
					normalOffset += sectionNormalCount;
					uvOffset += sectionUvs.length;
					sectionNormalCount = 0;
					sectionVertexCount = 0;

					sectionUvs.length = 0;
					faces.length = 0;
				}
			}
			else if (line.startsWith("v "))
			{
				lineParts = split(line[2..$], " ");
				models[currentModel].vertices ~= Vertex(
					                                    cast(short)(parse!float(lineParts[2]) * 256),
					                                    cast(short)(parse!float(lineParts[0]) * 256),
					                                    cast(short)(parse!float(lineParts[1]) * 256)
					                                   );
				sectionVertexCount++;
			}
			else if (line.startsWith("vn "))
			{
				lineParts = split(line[3..$], " ");
				models[currentModel].normals ~= Normal(
					                                   cast(byte)(parse!float(lineParts[2]) * 127),
					                                   cast(byte)(parse!float(lineParts[0]) * 127),
					                                   cast(byte)(parse!float(lineParts[1]) * 127)
					                                  );
				sectionNormalCount++;
			}
			else if (line.startsWith("vt "))
			{
				lineParts = split(line[3..$], " ");
				sectionUvs ~= TextureCoordinate(
					                            cast(byte)(parse!float(lineParts[0]) * 80),
					                            cast(byte)(parse!float(lineParts[1]) * 38)
					                           );
			}
			else if (line.startsWith("f "))
			{
				lineParts = split(line[2..$], " ");
				int found;
				int newValue;
				// TODO: might be a good idea to remove this face compression now I have quads from blender?
				if (lineParts.length == 3)
				{
					foreach (index, face; faces)
					{
						if (face.length == 3)
						{
							found = 0;
							newValue = 3;
							if (canFind(face, lineParts[0]))
							{
								found++;
							}
							if (canFind(face, lineParts[1]))
							{
								found++;
								newValue -= 1;
							}
							if (canFind(face, lineParts[2]))
							{
								found++;
								newValue -= 2;
							}
							if (found == 2)
							{
								faces[index] ~= lineParts[newValue];
								break;
							}
						}
					}
					if (found != 2)
					{
						faces ~= lineParts;
					}		
				}
				else
				{
					faces ~= lineParts;
				}
				
			}
			else if (line.startsWith("mtllib "))
			{
				lineParts = split(line, " ");
				if (canFind(lineParts[1], '\\') || canFind(lineParts[1], '/'))
				{
					materialPaths = texturePathsFromMtl(lineParts[1]);
				}
				else
				{
					int folderEndIndex = lastIndexOf(objFilePath, '/') != -1 ? lastIndexOf(objFilePath, '/') : lastIndexOf(objFilePath, '\\');
					string materialLibraryPath = objFilePath[0..folderEndIndex + 1] ~ lineParts[1];
					materialPaths = texturePathsFromMtl(materialLibraryPath);
				}
				foreach (path; materialPaths)
				{
					if (path != "")
					{
						bodyTextures ~= Png.pngToWdcTexture(path);
					}
					else
					{
						bodyTextures ~= new ubyte[8];
					}
				}
			}
			else if (line.startsWith("usemtl "))
			{
				lineParts = split(line, " ");
				int materialIndex = parse!int(lineParts[1]);
				if (currentModel == 0)
				{
					modelToTextureMap[currentModelSection] = materialIndex;
					palettesA[MODEL_TO_PALETTE[currentModelSection]] = Png.pngToWdcPalette(materialPaths[materialIndex]);
				}
			}
		}
		facesToPolygons();
		bodyTextures ~= Png.pngToWdcTexture("output\\0_car22_0.png");
		bodyTextures ~= Png.pngToWdcTexture("output\\0_car23_0.png");
		bodyTextures ~= Png.pngToWdcTexture("output\\0_car24_0.png");
		bodyTextures ~= Png.pngToWdcTexture("output\\0_car25_0.png");

		insertedPaletteIndices = [0,1,2,3,4,5,6,7];
		input.close();
		//removeRepeatedVertices();
		generateBinaries();
	}

	private string[] texturePathsFromMtl(string mtlLibraryPath)
	{
		import std.conv, std.string;

		string[] texturePaths = new string[0x16], lineParts;
		int textureNum;
		string line;
		File input = File(mtlLibraryPath, "r");
		while((line = input.readln()) !is null)
		{
			if (line.startsWith("newmtl "))
			{
				lineParts = split(line, " ");
				textureNum = parse!int(lineParts[1]);
			}
			if (line.startsWith("map_Kd "))
			{
				lineParts = split(line, "map_Kd ");
				texturePaths[textureNum] = chomp(lineParts[1]);
			}
		}
		input.close();
		return texturePaths;
	}

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
		uint textureDescriptorsSize = bodyTextures.length * 0x20;
		
		uint a0Start = FIXED_DATA_END + paletteSize + texturesSize + textureDescriptorsSize;
		uint a0Count = modelToTextureMap.length + 4; // +4 moving wheel textures
		// 0xA0
		binaryData ~= nativeToBigEndian(a0Start);
		binaryData ~= [0,0,0,0];
		binaryData ~= nativeToBigEndian(a0Count);
		// After the 3rd LoD there is the weird small texture, then the four moving wheel textures
		// for now lets leave out the small mutant and see what happens
		binaryData ~= [0,0,0,0,0,0,0,0];

		uint b4Start = a0Start + ((modelToTextureMap.length + 4) * 4);
		// 0xB4
		binaryData ~= nativeToBigEndian(b4Start);
		binaryData ~= [0,0,0,0xFF & bodyTextures.length];
		binaryData ~= [0,0,0,0,0,0,0,0,0,0,0,0];

		uint c8Start = b4Start + (bodyTextures.length * 4) + (4 * 0x20);
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
		
		uint[] textureDescriptorPointers = new uint[bodyTextures.length];
		uint insertedTexturePointer = FIXED_DATA_END + paletteSize;
		// Body texture descriptors
		foreach (i, texture; bodyTextures)
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
		binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 4]);
		binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 3]);
		binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 2]);
		binaryData ~= nativeToBigEndian(textureDescriptorPointers[$ - 1]);

		foreach (texturePointer; textureDescriptorPointers)
		{
			binaryData ~= nativeToBigEndian(texturePointer);
		}

		if (binaryData.length % 8 != 0) // pad to next doubleword
		{
			binaryData ~= new ubyte[8 - binaryData.length % 8];
		}
		// Moving wheel textures:
		insertedTexturePointer = FIXED_DATA_END + paletteSize + (((80 * 38) / 2) * (bodyTextures.length - 4));
		foreach (i, texture; bodyTextures[$-4..$])
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
		// models should be fixed size at 4?
		models.length = 4;
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
			foreach (normal; model.normals)
			{
				binaryData ~= [normal.z, normal.x, normal.y]; // OK not to cast?
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
		foreach(texture; bodyTextures)
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

	void outputWavefrontObj()
	{
		import std.conv;
		// Wheels are in order: front L, front R, rear L, rear R
		if (!exists("output") || !("output".isDir))
		{
			mkdir("output");
		}
		outputTextures(palettesA);
		outputTextures(palettesB, 1);
		outputTextures(palettesC, 2);
		File output = File("output/car.obj", "w");
		int normalOffset = 1;
		int vertexOffest = 1;
		int uvOffset = 1;
		output.writeln("mtllib car.mtl");
		output.writeln("o ", OBJ_WHEEL_ID);
		output.writeln("v ", wheelOrigins[0].x, " ", wheelOrigins[0].y, " ", wheelOrigins[0].z);
		output.writeln("v ", wheelOrigins[1].x, " ", wheelOrigins[1].y, " ", wheelOrigins[1].z);
		output.writeln("v ", wheelOrigins[2].x, " ", wheelOrigins[2].y, " ", wheelOrigins[2].z);
		output.writeln("v ", wheelOrigins[3].x, " ", wheelOrigins[3].y, " ", wheelOrigins[3].z);
		output.writeln("l 1 2 3 4 1");
		vertexOffest += 4;

		output.writeln("o ", OBJ_LIGHT_ID);
		output.writeln("v ", lightOrigins[0].x, " ", lightOrigins[0].y, " ", lightOrigins[0].z);
		output.writeln("v ", lightOrigins[1].x, " ", lightOrigins[1].y, " ", lightOrigins[1].z);
		output.writeln("v ", lightOrigins[2].x, " ", lightOrigins[2].y, " ", lightOrigins[2].z);
		output.writeln("v ", lightOrigins[3].x, " ", lightOrigins[3].y, " ", lightOrigins[3].z);
		output.writeln("l ", vertexOffest, " ", vertexOffest + 1, " ", vertexOffest + 2, " ", vertexOffest + 3, " ", vertexOffest);
		vertexOffest += 4;

		bool hasNormals;
		foreach (mIndex, currentModel; models)
		{
			foreach (vertex; currentModel.vertices)
			{
				output.writeln("v ", vertex.x / 256.0, " ",
				                     vertex.y / 256.0, " ",
				                     vertex.z / 256.0);
			}
			
			foreach (normal; currentModel.normals)
			{
				output.writeln("vn ", normal.x / 127.0, " ",
				                      normal.y / 127.0, " ",
				                      normal.z / 127.0);
			}

			foreach (sIndex, ms; currentModel.modelSections)
			{
				if (mIndex == 0)
				{
					output.writeln("usemtl ", modelToTextureMap[sIndex]);
					output.writefln("o %.2d-%.2d-%s", mIndex, sIndex, partNames[sIndex]);
				}
				else
				{
					output.writeln("usemtl ", 14);
					output.writefln("o %.2d-%.2d", mIndex, sIndex);
				}
				hasNormals = currentModel.normals.length > 0;
				foreach (polygon; ms.polygons)
				{
					foreach (uvi, uv; polygon.textureCoordinates)
					{
						output.writeln("vt ", uv.u / 80.0, " ", uv.v / 38.0);
					}
					output.write("f ", polygon.vertexIndices[0] + vertexOffest, "/-4/",
					                     hasNormals ? to!string(polygon.normalIndices[0] + normalOffset) : "", " ",

					                     polygon.vertexIndices[1] + vertexOffest, "/-3/",
					                     hasNormals ? to!string(polygon.normalIndices[1] + normalOffset) : "", " ",

					                     polygon.vertexIndices[2] + vertexOffest, "/-2/",
					                     hasNormals ? to!string(polygon.normalIndices[2] + normalOffset) : "");
					if (polygon.vertexIndices[3] != 0xFFFF)
					{
						//output.writeln("f ", polygon.vertexIndices[0] + vertexOffest, "/-4/",
						//                     hasNormals ? to!string(polygon.normalIndices[0] + normalOffset) : "", " ",

						//                     polygon.vertexIndices[2] + vertexOffest, "/-2/",
						//                     hasNormals ? to!string(polygon.normalIndices[2] + normalOffset) : "", " ",

						output.write(                     " ", polygon.vertexIndices[3] + vertexOffest, "/-1/",
						                     hasNormals ? to!string(polygon.normalIndices[3] + normalOffset) : "");
					}
					output.writeln("");
					uvOffset += 4;
				}
			}
			normalOffset += currentModel.normals.length;
			vertexOffest += currentModel.vertices.length;
		}
	}

	private void outputTextures(Colour[COLOURS_PER_PALETTE][] palettes, int paletteSet = 0)
	{
		enum byte TEXTURE_WIDTH = 80, TEXTURE_HEIGHT = 38;
		enum int TEXTURE_SIZE_BYTES = (TEXTURE_WIDTH * TEXTURE_HEIGHT) / 2;
		
		File materialLibraryFile = File("output/car.mtl", "w");
		Colour[] curPalette;
		ubyte[] texture;
		int alternate;
		foreach (modelIndex, textureNum; modelToTextureMap)
		{
			alternate = 0;
			texture = bodyTextures[textureNum];
			if (texture.length != TEXTURE_SIZE_BYTES)
			{
				continue;
			}
			if (modelIndex == 20 || modelIndex == 22)
			{
				alternate = 1;
			}
			materialLibraryFile.writeln("newmtl ", textureNum);
			materialLibraryFile.writeln("illum 0");
			materialLibraryFile.writeln(format("map_Kd -clamp on .\\%d_car%.2d_%d.png", 0, textureNum, alternate));
			
			File textureFile = File(format("output/%d_car%.2d_%d.png", paletteSet, textureNum, alternate), "wb");
			curPalette = palettes[MODEL_TO_PALETTE[modelIndex]];
			textureFile.rawWrite(Png.wdcTextureToPng(curPalette, texture, TEXTURE_WIDTH, TEXTURE_HEIGHT));
			textureFile.close();
		}
		materialLibraryFile.close();
	}

	private void parseBinaryTextures()
	{
		int modelToTexturePointers = binaryData.readInt(0xA0);
		int modelToTextureCount = binaryData.readInt(0xA8);
		modelToTextureMap.length = modelToTextureCount;

		int textureDescriptorPointers = binaryData.readInt(0xB4);
		int textureDescriptorCount = binaryData.readInt(0xB8);
		int descriptorLocation;
		int textureSizeInBytes;
		int texturePosition = 0;

		bodyTextures.length = textureDescriptorCount;
		
		foreach(index; 0..textureDescriptorCount)
		{
			descriptorLocation = binaryData.readInt(textureDescriptorPointers + (index * 4));
			textureSizeInBytes = (((binaryData.readInt(descriptorLocation + 0x14) >> 12) & 0xFFF) + 1) << 1;
			bodyTextures[index] = binaryTextures[texturePosition..texturePosition + textureSizeInBytes];
			if (textureSizeInBytes > 8)
			{
				wordSwapOddRows(bodyTextures[index], 40, 38);
			}
			texturePosition += textureSizeInBytes;
			
			foreach(mIndex; 0..modelToTextureCount)
			{
				if (binaryData.readInt(modelToTexturePointers + (mIndex * 4)) == descriptorLocation)
				{
					modelToTextureMap[mIndex] = index;
				}
			}
		}
		// The four "wheel texture descriptors" that come after the main lot are
		// always the same as the last four from the main lot, so can just copy them
	}

	private void wordSwapOddRows(ref ubyte[] rawTexture, int bytesWide, int textureHeight)
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

	private void parseBinaryPalettes(ubyte[] binaryPaletteSource, ref Colour[COLOURS_PER_PALETTE][PALETTES_PER_SET] destination)
	{
		foreach(index; 0..(COLOURS_PER_PALETTE * PALETTES_PER_SET))
		{
			destination[index / COLOURS_PER_PALETTE][index % COLOURS_PER_PALETTE] = Colour(binaryPaletteSource.readUshort(index * 2));
		}
	}

	private void parseBinaryFixedPalettes()
	{
		int palettePointerPointer = 0x7C;

		foreach(i; 0..PALETTES_PER_SET)
		{
			insertedPaletteIndices[i] = binaryData.readInt(palettePointerPointer);
			palettePointerPointer += 4;
		}

		for(int palettePointer = 0x398;; palettePointer += 0x20)
		{
			if (binaryData.readInt(palettePointer) != 0)
			{
				// fixed palette
				fixedPalettes ~= new Colour[COLOURS_PER_PALETTE];
				foreach(i; 0..COLOURS_PER_PALETTE)
				{
					fixedPalettes[$ - 1][i] = Colour(binaryData.readUshort(palettePointer + (i * 2)));
				}
			}
			else if (canFind(insertedPaletteIndices[], palettePointer))
			{
				// inserted palette
				fixedPalettes ~= null;
			}
			else
			{
				break;
			}
		}
		// set pointers relative to palette block index
		foreach(i; 0..PALETTES_PER_SET)
		{
			insertedPaletteIndices[i] = (insertedPaletteIndices[i] - 0x398) / 0x20;
		}
	}

	private void parseBinaryModels()
	{
		int nextModelSectionPointerSource = 0xF4;
		int modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
		int verticesPointer = 0, normalsPointer, polygonsPointer, verticesCount, normalsCount, polygonsCount;
		Model currentModel;
		ModelSection currentModelSection;
		while (modelSectionPointer != 0)
		{
			if (binaryData.readInt(modelSectionPointer) == modelSectionPointer)
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

				currentModel = Model(new Vertex[verticesCount], new Normal[normalsCount]);

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
				models ~= currentModel;
			}
			polygonsPointer = binaryData.readInt(modelSectionPointer + 8);
			polygonsCount   = binaryData.readInt(modelSectionPointer + 12);
			currentModelSection = ModelSection(new Polygon[polygonsCount]);
			foreach (i; 0..polygonsCount)
			{
				currentModelSection.polygons[i] =
					Polygon([binaryData.readUshort(polygonsPointer + 8  + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 10 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 12 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 14 + (i * 0x20))],
                            [TextureCoordinate(cast(byte)binaryData[polygonsPointer + 16 + (i * 0x20)],
                            	               cast(byte)binaryData[polygonsPointer + 17 + (i * 0x20)]),
                             TextureCoordinate(cast(byte)binaryData[polygonsPointer + 18 + (i * 0x20)],
                             	               cast(byte)binaryData[polygonsPointer + 19 + (i * 0x20)]),
                             TextureCoordinate(cast(byte)binaryData[polygonsPointer + 20 + (i * 0x20)],
                             	               cast(byte)binaryData[polygonsPointer + 21 + (i * 0x20)]),
                             TextureCoordinate(cast(byte)binaryData[polygonsPointer + 22 + (i * 0x20)],
                             	               cast(byte)binaryData[polygonsPointer + 23 + (i * 0x20)])],
                            [binaryData.readUshort(polygonsPointer + 24 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 26 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 28 + (i * 0x20)),
                             binaryData.readUshort(polygonsPointer + 30 + (i * 0x20))]
                           );
			}
			models[$ - 1].modelSections ~= currentModelSection;

			nextModelSectionPointerSource += 0x10;
			modelSectionPointer = binaryData.readInt(nextModelSectionPointerSource);
		}
	}
}
