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

		enum COLOURS_PER_PALETTE = 0x10;
		enum PALETTES_PER_SET = 8;
		enum OBJ_WHEEL_ID = "wheel_origins";
		enum OBJ_LIGHT_ID = "light_origins";

		const string[] partNames = ["grill", "bonnet_l", "bonnet_r", "windscreen_f", "roof", "windscreen_b", "trunk",
		                            "back", "wheel_well_fl", "wheel_well_fr", "wheel_well_bl", "wheel_well_br",
		                            "door_l", "door_r", "windows_l", "windows_r", "spoiler", "undercarriage", "part_x",
		                            "headlight_l", "headlight_r", "taillight_l", "taillight_r",
		                            "wingmirror_l", "wingmirror_r", "roof_ornament", "LoD1", "LoD2", "LoD3"];

		float unknown1;
		float carCameraYOffset;
		// Both these are Z X Y
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
		
		int currentModel, currentModelSection,
		    vertexOffset, sectionVertexCount,
		    normalOffset, sectionNormalCount,
		    uvOffset;
		string line, materialLibraryPath;
		string[] lineParts;
		TextureCoordinate[] sectionUvs;
		string[][] faces;
		File input = File(objFilePath, "r");
		while((line = input.readln()) !is null)
		{
			line = chomp(line);
			
			if (line.startsWith("o "))
			{
				lineParts = split(line[2..$], "-");
				if (lineParts[0] == OBJ_WHEEL_ID)
				{
					foreach (i; 0..4)
					{
						line = input.readln();
						lineParts = split(line[2..$], " ");
						wheelOrigins[i] = vec3f(parse!float(lineParts[2]), parse!float(lineParts[0]), parse!float(lineParts[1]));
					}
					vertexOffset += 4;
				}
				else if (lineParts[0] == OBJ_LIGHT_ID)
				{
					foreach (i; 0..4)
					{
						line = input.readln();
						lineParts = split(line[2..$], " ");
						lightOrigins[i] = vec3f(parse!float(lineParts[2]), parse!float(lineParts[0]), parse!float(lineParts[1]));
					}
					vertexOffset += 4;
				}
				else if (lineParts.length >= 2)
				{
					// TODO convert faces into polygons for current section here.
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
					vertexOffset += sectionVertexCount;
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
			else if (line.startsWith("usemtl "))
			{
				lineParts = split(line, " ");
				int materialIndex = parse!int(lineParts[1]);
				if (modelToTextureMap.length <= currentModelSection)
				{
					modelToTextureMap.length = currentModelSection + 1;
				}
				if (currentModel == 0)
				{
					modelToTextureMap[currentModelSection] = materialIndex;
				}
			}
		}

		input.close();
		// convert to binary files
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
					output.writeln("usemtl ", 22 + sIndex);
					output.writefln("o %.2d-%.2d", mIndex, sIndex);
				}
				hasNormals = currentModel.normals.length > 0;
				foreach (polygon; ms.polygons)
				{
					foreach (uvi, uv; polygon.textureCoordinates)
					{
						output.writeln("vt ", uv.u / 80.0, " ", uv.v / 38.0);
					}
					output.writeln("f ", polygon.vertexIndices[0] + vertexOffest, "/-4/",
					                     hasNormals ? to!string(polygon.normalIndices[0] + normalOffset) : "", " ",

					                     polygon.vertexIndices[1] + vertexOffest, "/-3/",
					                     hasNormals ? to!string(polygon.normalIndices[1] + normalOffset) : "", " ",

					                     polygon.vertexIndices[2] + vertexOffest, "/-2/",
					                     hasNormals ? to!string(polygon.normalIndices[2] + normalOffset) : "");
					if (polygon.vertexIndices[3] != 0xFFFF)
					{
						output.writeln("f ", polygon.vertexIndices[0] + vertexOffest, "/-4/",
						                     hasNormals ? to!string(polygon.normalIndices[0] + normalOffset) : "", " ",

						                     polygon.vertexIndices[2] + vertexOffest, "/-2/",
						                     hasNormals ? to!string(polygon.normalIndices[2] + normalOffset) : "", " ",

						                     polygon.vertexIndices[3] + vertexOffest, "/-1/",
						                     hasNormals ? to!string(polygon.normalIndices[3] + normalOffset) : "");
					}
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

		const byte[] bmpHeader = [0x42, 0x4D, 0,0,0,0, 0,0, 0,0, 54,0,0,0, 40,0,0,0, 
		                          TEXTURE_WIDTH,0,0,0, TEXTURE_HEIGHT,0,0,0, 1,0, 16,0,
		                          0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
		ubyte[] modelToPalMap = [0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,1,
		                         0,1,2,4,5,6,7,1,1,1,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2];
		
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
			materialLibraryFile.writeln(format("map_Kd -clamp on .\\%d_car%.2d_%d.bmp", 0, textureNum, alternate));
			
			File textureFile = File(format("output/%d_car%.2d_%d.bmp", paletteSet, textureNum, alternate), "wb");
			textureFile.rawWrite(bmpHeader);
			curPalette = palettes[modelToPalMap[modelIndex]];
			for (int i = 0; i < TEXTURE_SIZE_BYTES; i += 2)
			{
				textureFile.rawWrite([cast(byte)(curPalette[(texture[i] & 0xf0) >>> 4].whole >>> 1)]);
				textureFile.rawWrite([cast(byte)(curPalette[(texture[i] & 0xf0) >>> 4].whole >>> 9)]);
				textureFile.rawWrite([cast(byte)(curPalette[texture[i] & 0xf].whole >>> 1)]);
				textureFile.rawWrite([cast(byte)(curPalette[texture[i] & 0xf].whole >>> 9)]);
				
				textureFile.rawWrite([cast(byte)(curPalette[(texture[i + 1] & 0xf0) >>> 4].whole >>> 1)]);
				textureFile.rawWrite([cast(byte)(curPalette[(texture[i + 1] & 0xf0) >>> 4].whole >>> 9)]);
				textureFile.rawWrite([cast(byte)(curPalette[texture[i + 1] & 0xf].whole >>> 1)]);
				textureFile.rawWrite([cast(byte)(curPalette[texture[i + 1] & 0xf].whole >>> 9)]);
			}
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
