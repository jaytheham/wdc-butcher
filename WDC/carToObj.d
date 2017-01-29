module wdc.carToObj;

import std.stdio, std.file, wdc.car, gfm.math;

static class CarToObj
{
	static void convert(Car car, string destinationFolder)
	{
		import std.conv;
		import std.algorithm.searching : countUntil;
		
		if (!exists(destinationFolder) || !(destinationFolder.isDir))
		{
			mkdir(destinationFolder);
		}
		outputTextures(car, 2, destinationFolder);
		outputTextures(car, 1, destinationFolder);
		outputTextures(car, 0, destinationFolder);

		File output = File(destinationFolder ~ "car.obj", "w");

		output.writeln("mtllib car.mtl");

		output.writeln("o ", Car.OBJ_WHEEL_ID);
		output.writeln("v ", car.wheelOrigins[0].x, " ", car.wheelOrigins[0].y, " ", car.wheelOrigins[0].z);
		output.writeln("v ", car.wheelOrigins[1].x, " ", car.wheelOrigins[1].y, " ", car.wheelOrigins[1].z);
		output.writeln("v ", car.wheelOrigins[2].x, " ", car.wheelOrigins[2].y, " ", car.wheelOrigins[2].z);
		output.writeln("v ", car.wheelOrigins[3].x, " ", car.wheelOrigins[3].y, " ", car.wheelOrigins[3].z);
		output.writeln("l 1 2 3 4 1");

		output.writeln("o ", Car.OBJ_LIGHT_ID);
		output.writeln("v ", car.lightOrigins[0].x, " ", car.lightOrigins[0].y, " ", car.lightOrigins[0].z);
		output.writeln("v ", car.lightOrigins[1].x, " ", car.lightOrigins[1].y, " ", car.lightOrigins[1].z);
		output.writeln("v ", car.lightOrigins[2].x, " ", car.lightOrigins[2].y, " ", car.lightOrigins[2].z);
		output.writeln("v ", car.lightOrigins[3].x, " ", car.lightOrigins[3].y, " ", car.lightOrigins[3].z);
		output.writeln("l 5 6 7 8 5");

		bool hasNormals;
		bool hasFourVerts = false;
		int vertexTotal = 8, normalTotal = 0, uvTotal = 0;
		vec3s[] vertexCache;
		vec3b[] normalCache;
		vec2b[] uvCache;
		int[4] objVertexIndices;
		int[4] objNormalIndices;
		int[4] objUvIndices;
		foreach (modelIndex, model; car.models)
		{
			foreach (sectionIndex, section; model.modelSections)
			{
				if (modelIndex == 0)
				{
					
					output.writefln("o %.2d-%.2d-%s", modelIndex, sectionIndex, Car.partNames[sectionIndex]);
					output.writeln("usemtl ", car.modelToTextureMap[sectionIndex]);
				}
				else
				{
					
					output.writefln("o %.2d-%.2d", modelIndex, sectionIndex);
					output.writeln("usemtl ", 14);
				}
				vertexTotal += vertexCache.length;
				normalTotal += normalCache.length;
				uvTotal += uvCache.length;
				vertexCache.length = 0;
				normalCache.length = 0;
				uvCache.length = 0;
				hasNormals = model.normals.length > 0;
				foreach (polygon; section.polygons)
				{
					foreach (pi, polygonIndex; polygon.vertexIndices)
					{
						if (polygonIndex == 0xFFFF) // will always be the last index
						{
							hasFourVerts = false;
							continue;
						}
						vec3s vertex = model.vertices[polygonIndex];
						if (countUntil(vertexCache, vertex) == -1)
						{
							output.writeln("v ", vertex.x / 256.0, " ",
							                     vertex.y / 256.0, " ",
							                     vertex.z / 256.0);
							vertexCache ~= vertex;
							objVertexIndices[pi] = vertexCache.length;
						}
						else
						{
							objVertexIndices[pi] = countUntil(vertexCache, vertex) + 1;
						}
						
						hasFourVerts = true;
					}
					if (hasNormals)
					{
						foreach (ni, normalIndex; polygon.normalIndices)
						{
							vec3b normal = model.normals[normalIndex];
							if (countUntil(normalCache, normal) == -1)
							{
								output.writeln("vn ", normal.x / 127.0, " ",
								                      normal.y / 127.0, " ",
								                      normal.z / 127.0);
								normalCache ~= normal;
								objNormalIndices[ni] = normalCache.length;
							}
							else
							{
								objNormalIndices[ni] = countUntil(normalCache, normal) + 1;
							}
							
						}
					}
					foreach (uvi, uv; polygon.textureCoordinates)
					{
						if (countUntil(uvCache, uv) == -1)
						{
							output.writeln("vt ", uv.x / 80.0, " ", uv.y / 38.0);
							uvCache ~= uv;
							objUvIndices[uvi] = uvCache.length;
						}
						else
						{
							objUvIndices[uvi] = countUntil(uvCache, uv) + 1;
						}
						
					}
					output.write("f ", objVertexIndices[0] + vertexTotal, "/",
						               objUvIndices[0] + uvTotal, "/",
					                   hasNormals ? to!string(objNormalIndices[0] + normalTotal) : "", " ",

					                   objVertexIndices[1] + vertexTotal, "/",
					                   objUvIndices[1] + uvTotal, "/",
					                   hasNormals ? to!string(objNormalIndices[1] + normalTotal) : "", " ",

					                   objVertexIndices[2] + vertexTotal, "/",
					                   objUvIndices[2] + uvTotal, "/",
					                   hasNormals ? to!string(objNormalIndices[2] + normalTotal) : "");
					if (hasFourVerts)
					{
						output.write(" ", objVertexIndices[3] + vertexTotal, "/",
						                  objUvIndices[3] + uvTotal, "/",
						                  hasNormals ? to!string(objNormalIndices[3] + normalTotal) : "");
					}
					output.writeln("");
				}
			}
		}
		output.close();
	}

	private static void outputTextures(Car car, int paletteSet, string destinationFolder)
	{
		import wdc.png;
		import std.string : format;
		enum byte TEXTURE_WIDTH = Car.TEXTURE_WIDTH_BYTES * 2;
		enum byte TEXTURE_HEIGHT = Car.TEXTURE_HEIGHT_BYTES;
		
		File materialLibrary = File(destinationFolder ~ "car.mtl", "w");
		Car.Colour[] palette;
		string fileName;
		int previousTextureIndex = -1;

		void writeTexture(ubyte[] textureBytes, int textureNum, int modelNum, int forceLitPalette)
		{
			uint paletteIndex = Car.MODEL_TO_PALETTE[modelNum] + forceLitPalette;
			fileName = modelNum > 29
			           ? format("set%d_wheel_%d.png", paletteSet, modelNum - 30)
			           : format("set%d_tex%.2d_pal%.2d.png", paletteSet, textureNum, paletteIndex);
			
			File textureFile = File(destinationFolder ~ fileName, "wb");
			palette = car.paletteSets[paletteSet][paletteIndex];
			textureFile.rawWrite(Png.wdcTextureToPng(palette, textureBytes, TEXTURE_WIDTH, TEXTURE_HEIGHT));
			textureFile.close();
		}
		void writeMtl(int textureNum)
		{
			materialLibrary.writeln("newmtl ", textureNum);
			materialLibrary.writeln("illum 1");
			materialLibrary.writeln("map_Kd " ~ fileName);
		}

		int wheelNum = 0;
		foreach (textureIndex, texture; car.textures)
		{
			if (texture.length != Car.TEXTURE_SIZE_BYTES)
			{
				continue;
			}
			foreach (modelIndex, mapTextureIndex; car.modelToTextureMap)
			{
				if (mapTextureIndex == textureIndex)
				{
					// TODO: some cars have a third palette for the rear lights when reversing?
					writeTexture(texture, textureIndex, modelIndex > 29 ? 30 + wheelNum++ : modelIndex, 0);
					if (modelIndex == 19 || modelIndex == 21)
					{
						writeTexture(texture, textureIndex, modelIndex, 1);
					}
					if (textureIndex != previousTextureIndex)
					{
						writeMtl(textureIndex);
						previousTextureIndex = textureIndex;
					}
				}
			}
		}
		materialLibrary.close();
	}
}